//
//  CDRUpdateOperation.m
//  Conductor
//

#import "CDRUpdateOperation.h"
#import "CDRAppRegistration.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRDevModeSession.h"
#import "CDRArtifactDownloader.h"
#import "CDRArtifactStager.h"
#import "CDRCodeSignature.h"
#import "CDRNotarizationCheck.h"
#import "CDRQuarantine.h"
#import "CDRQuitMonitor.h"
#import "CDRAtomicSwapper.h"
#import "CDRPrivilegedHelperManager.h"
#import "CDRVersion.h"
#import "CDRErrors.h"

NSString *CDRUpdatePhaseName(CDRUpdatePhase phase) {
    switch (phase) {
        case CDRUpdatePhaseIdle:         return @"Idle";
        case CDRUpdatePhaseFetching:     return @"Fetching manifest";
        case CDRUpdatePhaseDownloading:  return @"Downloading";
        case CDRUpdatePhaseExtracting:   return @"Extracting";
        case CDRUpdatePhaseVerifying:    return @"Verifying";
        case CDRUpdatePhaseAwaitingQuit: return @"Waiting for app to quit";
        case CDRUpdatePhaseSwapping:     return @"Installing";
        case CDRUpdatePhaseFinishing:    return @"Finishing";
        case CDRUpdatePhaseDone:         return @"Done";
        case CDRUpdatePhaseFailed:       return @"Failed";
    }
    return @"Unknown";
}

@interface CDRUpdateOperation ()
@property (nonatomic, readwrite) CDRUpdatePhase phase;
@property (nonatomic, readwrite) CDRAppRegistration *registration;
@property (nonatomic) CDRManifest *manifest;
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic, weak) id<CDRUpdateOperationDelegate> delegate;

@property (nonatomic) dispatch_queue_t workQueue;
@property (nonatomic) CDRManifestFetcher *fetcher;
@property (nonatomic) CDRArtifactDownloader *downloader;
@property (nonatomic) CDRArtifactStager *stager;
@property (nonatomic) CDRQuitMonitor *quitMonitor;
@property (nonatomic) CDRAtomicSwapper *swapper;
@property (nonatomic) CDRPrivilegedHelperManager *helperManager;

@property (nonatomic, nullable) NSURL *stagingURL;
@property (nonatomic, nullable) NSString *pinnedTeamID;
/// Captured in stepVerify: for the pre-swap freshness re-guard.
@property (nonatomic, readwrite, nullable) NSString *stagedShortVersion;
@property (nonatomic, readwrite, nullable) NSString *stagedBuildVersion;
@property (atomic, readwrite, getter=isParkedAwaitingQuit) BOOL parkedAwaitingQuit;
@property (nonatomic) BOOL appWasQuitByFlow;
@property (nonatomic) BOOL started;
@end

@implementation CDRUpdateOperation

- (instancetype)initWithRegistration:(CDRAppRegistration *)registration
                            manifest:(CDRManifest *)manifest
                             session:(CDRDevModeSession *)session
                            delegate:(id<CDRUpdateOperationDelegate>)delegate {
    self = [super init];
    if (!self) return nil;
    _registration = registration;
    _manifest = manifest;
    _session = session;
    _delegate = delegate;
    _workQueue = dispatch_queue_create("com.ranvel.Conductor.update", DISPATCH_QUEUE_SERIAL);
    _fetcher = [[CDRManifestFetcher alloc] initWithSession:session];
    _downloader = [[CDRArtifactDownloader alloc] initWithSession:session];
    _stager = [[CDRArtifactStager alloc] init];
    _quitMonitor = [[CDRQuitMonitor alloc] init];
    _swapper = [[CDRAtomicSwapper alloc] init];
    // Lazily used: obtaining the singleton registers nothing (registration
    // happens inside installHelperWithError:, only when a swap needs root).
    _helperManager = [CDRPrivilegedHelperManager sharedManager];
    _phase = CDRUpdatePhaseIdle;
    return self;
}

#pragma mark - Delegate plumbing

- (void)enterPhase:(CDRUpdatePhase)phase {
    self.phase = phase;
    id<CDRUpdateOperationDelegate> delegate = self.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate updateOperation:self didEnterPhase:phase];
    });
}

- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    id<CDRUpdateOperationDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(updateOperation:logMessage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate updateOperation:self logMessage:message];
        });
    }
}

/// Terminal failure: clean staging, report. The installed app was never
/// touched — everything before the swap operates only inside staging.
- (void)failWithError:(NSError *)error {
    if (self.stagingURL) {
        [self.stager removeStagingDirectoryForBundleID:self.registration.bundleID
                                       nearDestination:self.registration.appURL];
        self.stagingURL = nil;
    }
    [self enterPhase:CDRUpdatePhaseFailed];
    id<CDRUpdateOperationDelegate> delegate = self.delegate;
    BOOL wasQuit = self.appWasQuitByFlow;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate updateOperation:self didFinishWithError:error appWasQuitByFlow:wasQuit];
    });
}

- (void)succeed {
    [self enterPhase:CDRUpdatePhaseDone];
    id<CDRUpdateOperationDelegate> delegate = self.delegate;
    BOOL wasQuit = self.appWasQuitByFlow;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate updateOperation:self didFinishWithError:nil appWasQuitByFlow:wasQuit];
    });
}

#pragma mark - Pipeline

- (void)start {
    NSAssert(!self.started, @"CDRUpdateOperation is one-shot");
    self.started = YES;
    dispatch_async(self.workQueue, ^{ [self stepCaptureAnchor]; });
}

/// §0 — capture the installed copy's identity. The Team ID read here is the
/// trust anchor for every later check. Unsigned/ad-hoc → refuse before any
/// network traffic.
- (void)stepCaptureAnchor {
    [self enterPhase:CDRUpdatePhaseFetching];

    NSError *error = nil;
    NSString *team = [CDRCodeSignature teamIdentifierForBundleAtURL:self.registration.appURL error:&error];
    if (!team) {
        // Attach the bundle ID to the generic signature error.
        [self failWithError:CDRError((CDRErrorCode)error.code, self.registration.bundleID,
                                     error.userInfo[NSUnderlyingErrorKey], nil)];
        return;
    }
    self.pinnedTeamID = team;
    [self log:@"%@: installed Team ID %@ is the trust anchor.", self.registration.bundleID, team];
    [self stepRefetchManifest];
}

/// Last-moment re-check (retraction.md): hours may pass between notification
/// and install. Fetch fresh; if the advertised version dropped below what the
/// user was shown, abort cleanly.
- (void)stepRefetchManifest {
    NSString *shownVersion = self.manifest.version;
    [self.fetcher fetchManifestForRegistration:self.registration
                                    completion:^(CDRManifest *fresh, NSError *error) {
        dispatch_async(self.workQueue, ^{
            if (!fresh) {
                [self failWithError:error];
                return;
            }
            if ([CDRVersion compare:fresh.version to:shownVersion] == NSOrderedAscending) {
                [self log:@"%@: advertised version regressed from %@ to %@ since notification — the developer retracted the update.",
                    self.registration.bundleID, shownVersion, fresh.version];
                [self failWithError:CDRError(CDRErrorDowngradeRefused, self.registration.bundleID, nil,
                    @{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"%@: the developer retracted update %@. You already have the latest build (%@).",
                        self.registration.bundleID, shownVersion, self.registration.installedShortVersion]})];
                return;
            }
            self.manifest = fresh;
            [self stepDownload];
        });
    }];
}

- (void)stepDownload {
    [self enterPhase:CDRUpdatePhaseDownloading];

    NSError *error = nil;
    self.stagingURL = [self.stager createStagingDirectoryForBundleID:self.registration.bundleID
                                                     nearDestination:self.registration.appURL
                                                               error:&error];
    if (!self.stagingURL) {
        [self failWithError:error];
        return;
    }

    [self log:@"%@: downloading %@", self.registration.bundleID, self.manifest.artifactURL.absoluteString];
    id<CDRUpdateOperationDelegate> delegate = self.delegate;
    void (^progress)(double) = nil;
    if ([delegate respondsToSelector:@selector(updateOperation:didUpdateDownloadProgress:)]) {
        progress = ^(double fractionCompleted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate updateOperation:self didUpdateDownloadProgress:fractionCompleted];
            });
        };
    }
    [self.downloader downloadArtifactAtURL:self.manifest.artifactURL
                               forBundleID:self.registration.bundleID
                        toStagingDirectory:self.stagingURL
                            expectedSHA256:self.manifest.sha256
                                  progress:progress
                                completion:^(NSURL *fileURL, NSError *dlError) {
        dispatch_async(self.workQueue, ^{
            if (!fileURL) {
                [self failWithError:dlError];
                return;
            }
            [self stepExtract:fileURL];
        });
    }];
}

- (void)stepExtract:(NSURL *)artifactURL {
    [self enterPhase:CDRUpdatePhaseExtracting];

    NSError *error = nil;
    NSURL *stagedApp = [self.stager extractArtifactAtURL:artifactURL
                                      toStagingDirectory:self.stagingURL
                                                bundleID:self.registration.bundleID
                                                   error:&error];
    if (!stagedApp) {
        [self failWithError:error];
        return;
    }
    [self stepVerify:stagedApp];
}

/// §3 — the whole ballgame. All checks run against the STAGED bundle, in order.
- (void)stepVerify:(NSURL *)stagedApp {
    [self enterPhase:CDRUpdatePhaseVerifying];
    NSString *bundleID = self.registration.bundleID;

    // 3.1 Bundle ID match — TCC grants and user expectations key on it.
    // Read the staged Info.plist directly: NSBundle caches per URL for the
    // process lifetime, and the staging path is deterministic, so a second
    // attempt for the same app would otherwise verify against the first
    // attempt's cached identity.
    NSDictionary *stagedInfo = [NSDictionary dictionaryWithContentsOfURL:
        [stagedApp URLByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *stagedBundleID = [stagedInfo[@"CFBundleIdentifier"] isKindOfClass:[NSString class]]
        ? stagedInfo[@"CFBundleIdentifier"] : nil;
    if (![stagedBundleID isEqualToString:bundleID]) {
        [self failWithError:CDRError(CDRErrorBundleIDMismatch, bundleID, nil, nil)];
        return;
    }

    // 3.2 Version sanity — from the staged Info.plist, never the manifest.
    // Load-bearing against replay of an older validly-signed build.
    NSString *stagedShort = stagedInfo[@"CFBundleShortVersionString"];
    NSString *stagedBuild = [stagedInfo[@"CFBundleVersion"] isKindOfClass:[NSString class]]
        ? stagedInfo[@"CFBundleVersion"] : nil;
    if (![stagedShort isKindOfClass:[NSString class]] || stagedShort.length == 0) {
        [self failWithError:CDRError(CDRErrorNotAnUpgrade, bundleID, nil, nil)];
        return;
    }
    BOOL newer = [CDRVersion isVersion:stagedShort build:stagedBuild
                             newerThan:self.registration.installedShortVersion
                                 build:self.registration.installedBuildVersion];
    if (!newer) {
        NSComparisonResult cmp = [CDRVersion compare:stagedShort to:self.registration.installedShortVersion];
        CDRErrorCode code = (cmp == NSOrderedAscending) ? CDRErrorDowngradeRefused : CDRErrorNotAnUpgrade;
        [self failWithError:CDRError(code, bundleID, nil, nil)];
        return;
    }
    self.stagedShortVersion = stagedShort;
    self.stagedBuildVersion = stagedBuild;
    [self log:@"%@: staged %@ (%@) > installed %@ (%@).", bundleID,
        stagedShort, stagedBuild ?: @"-",
        self.registration.installedShortVersion, self.registration.installedBuildVersion ?: @"-"];

    // 3.3 Signature validity with the pinned Team ID.
    NSError *sigError = nil;
    if (![CDRCodeSignature validateBundleAtURL:stagedApp
                                  pinnedTeamID:self.pinnedTeamID
                                         error:&sigError]) {
        [self failWithError:CDRError((CDRErrorCode)sigError.code, bundleID,
                                     sigError.userInfo[NSUnderlyingErrorKey], nil)];
        return;
    }
    [self log:@"%@: signature valid for pinned Team ID %@.", bundleID, self.pinnedTeamID];

    // 3.4 Notarization — Apple's ticket exists for exactly this bundle.
    NSError *notarizationError = nil;
    if (![CDRNotarizationCheck assessBundleAtURL:stagedApp error:&notarizationError]) {
        [self failWithError:CDRError(CDRErrorNotarizationRejected, bundleID, nil,
                                     notarizationError.userInfo)];
        return;
    }
    [self log:@"%@: notarization assessment passed.", bundleID];

    // §6 (sequenced pre-swap) — strip quarantine on the STAGED bundle so the
    // atomic swap remains the sole mutation of /Applications.
    NSError *quarantineError = nil;
    if (![CDRQuarantine stripQuarantineRecursivelyAtURL:stagedApp error:&quarantineError]) {
        [self failWithError:CDRError(CDRErrorExtractFailed, bundleID, quarantineError, nil)];
        return;
    }

    [self stepQuitCheck:stagedApp];
}

/// §4 — never force-terminate; the user decides.
- (void)stepQuitCheck:(NSURL *)stagedApp {
    NSString *bundleID = self.registration.bundleID;
    NSArray<NSRunningApplication *> *running = [CDRQuitMonitor runningInstancesOfBundleID:bundleID];
    if (running.count == 0) {
        dispatch_async(self.workQueue, ^{ [self stepSwap:stagedApp]; });
        return;
    }

    [self enterPhase:CDRUpdatePhaseAwaitingQuit];
    id<CDRUpdateOperationDelegate> delegate = self.delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate updateOperation:self requestsQuitDecisionFor:running reply:^(CDRQuitDecision decision) {
            switch (decision) {
                case CDRQuitDecisionSkip: {
                    dispatch_async(self.workQueue, ^{
                        [self failWithError:CDRError(CDRErrorUserDeclinedQuit, bundleID, nil, nil)];
                    });
                    return;
                }

                case CDRQuitDecisionQuitAndUpdate: {
                    [self.quitMonitor requestQuitOfBundleID:bundleID timeout:30 completion:^(BOOL allQuit) {
                        dispatch_async(self.workQueue, ^{
                            if (!allQuit) {
                                [self failWithError:CDRError(CDRErrorAppStillRunning, bundleID, nil, nil)];
                                return;
                            }
                            self.appWasQuitByFlow = YES;
                            [self stepSwap:stagedApp];
                        });
                    }];
                    return;
                }

                case CDRQuitDecisionUpdateOnQuit: {
                    // Park: verified and staged; swap when the app exits on
                    // its own. appWasQuitByFlow stays NO — the user quit
                    // deliberately, so no relaunch offer.
                    self.parkedAwaitingQuit = YES;
                    [self log:@"%@: update will install when the app quits.", bundleID];
                    [self.quitMonitor observeTerminationOfBundleID:bundleID completion:^{
                        dispatch_async(self.workQueue, ^{
                            if (!self.parkedAwaitingQuit) return; // canceled first
                            self.parkedAwaitingQuit = NO;
                            [self stepSwap:stagedApp];
                        });
                    }];
                    return;
                }
            }
        }];
    });
}

- (void)cancelParkedUpdate {
    dispatch_async(dispatch_get_main_queue(), ^{
        // The monitor is main-queue-bound; cancel there first so a not-yet-
        // delivered termination can no longer fire.
        [self.quitMonitor cancelObservation];
        dispatch_async(self.workQueue, ^{
            if (!self.parkedAwaitingQuit) return; // already swapping or done
            self.parkedAwaitingQuit = NO;
            [self failWithError:CDRError(CDRErrorUpdateCancelled, self.registration.bundleID, nil, nil)];
        });
    });
}

/// §5 — the single mutation of /Applications.
- (void)stepSwap:(NSURL *)stagedApp {
    NSString *bundleID = self.registration.bundleID;

    // Freshness re-guard: the installed copy may have changed since stepVerify
    // ran — a parked wait can last days and the app may update itself. Re-read
    // the installed Info.plist directly (NSBundle caches per URL) and refuse
    // unless the staged bundle is still strictly newer. Nothing was touched.
    NSDictionary *installedInfo = [NSDictionary dictionaryWithContentsOfURL:
        [self.registration.appURL URLByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *installedShort = installedInfo[@"CFBundleShortVersionString"];
    if ([installedShort isKindOfClass:[NSString class]] && self.stagedShortVersion) {
        NSString *installedBuild = installedInfo[@"CFBundleVersion"];
        if (![CDRVersion isVersion:self.stagedShortVersion build:self.stagedBuildVersion
                         newerThan:installedShort
                             build:([installedBuild isKindOfClass:[NSString class]] ? installedBuild : nil)]) {
            [self log:@"%@: installed copy is now %@ (was %@ when verified) — the staged update is no longer an upgrade.",
                bundleID, installedShort, self.registration.installedShortVersion];
            [self failWithError:CDRError(CDRErrorNotAnUpgrade, bundleID, nil, nil)];
            return;
        }
    }

    [self enterPhase:CDRUpdatePhaseSwapping];

    NSURL *backup = nil;
    NSError *error = nil;
    BOOL ok = [self.swapper swapInstalledAppAtURL:self.registration.appURL
                               withStagedAppAtURL:stagedApp
                                         bundleID:bundleID
                                        backupURL:&backup
                                            error:&error];
    if (ok) {
        [self finishSwapWithBackupURL:backup bundleID:bundleID];
        return;
    }

    // The unprivileged swap failed. If privilege might fix it — a root-owned
    // install, or a TCC/App-Management denial of /Applications — escalate to the
    // root helper; otherwise fail as before. Either way the installed app is
    // still untouched (CDRAtomicSwapper guarantees it), so we stay in Swapping
    // through the escalation rather than adding a phase.
    if (![self swapErrorWarrantsEscalation:error]) {
        [self failWithError:error];
        return;
    }
    [self log:@"%@: unprivileged swap failed — %@", bundleID, error.localizedDescription];
    [self logSwapErrorChain:error bundleID:bundleID];
    [self escalateSwapForStagedApp:stagedApp bundleID:bundleID];
}

/// Post-swap tail, shared by the unprivileged and privileged paths so they
/// converge instead of duplicating: record the swap, move to Finishing, trash
/// the displaced bundle (non-fatal), clean staging, succeed. `backup` may be nil
/// (the helper can report success with no displaced bundle to trash).
- (void)finishSwapWithBackupURL:(nullable NSURL *)backup bundleID:(NSString *)bundleID {
    [self log:@"%@: swapped in new bundle.", bundleID];

    [self enterPhase:CDRUpdatePhaseFinishing];

    // Displaced bundle → Trash. Non-fatal: on failure it merely lingers.
    // When the privileged helper performed the swap, the displaced bundle is
    // root-owned, so recycleURLs: from this user-level process may itself fail —
    // still non-fatal (a helper-side trash is possible follow-up work).
    if (backup) {
        [self.swapper trashDisplacedBundleAtURL:backup completion:^(NSError *trashError) {
            if (trashError) {
                [self log:@"%@: could not move the old bundle to the Trash (%@) — it remains at %@.",
                    bundleID, trashError.localizedDescription, backup.path];
            } else {
                [self log:@"%@: old bundle moved to the Trash.", bundleID];
            }
        }];
    }

    // Clean staging; TCC grants survive automatically (bundle ID + signing
    // identity unchanged — guaranteed by 3.1/3.3). Nothing to do for them.
    [self.stager removeStagingDirectoryForBundleID:bundleID
                                   nearDestination:self.registration.appURL];
    self.stagingURL = nil;
    [self succeed];
}

/// Whether a failed unprivileged swap should be retried through the privileged
/// helper. YES for an explicit permission classification (EPERM/EACCES/read-only
/// chain, already mapped to CDRErrorPermissionDenied by CDRAtomicSwapper), or an
/// NSFileWriteUnknownError (NSCocoaErrorDomain 512) anywhere in the underlying
/// chain — the shape a TCC/App-Management denial of /Applications takes with no
/// POSIX error beneath it. Escalating on a 512 the helper also can't fix is
/// acceptable: we then fail with the helper's error, no worse than failing here.
/// Errors from before the swap (CDRErrorNotAnUpgrade, verification, …) never
/// reach this method — it is only consulted at the swap site.
- (BOOL)swapErrorWarrantsEscalation:(NSError *)error {
    if ([error.domain isEqualToString:CDRErrorDomain] &&
        error.code == CDRErrorPermissionDenied) {
        return YES;
    }
    for (NSError *e = error; e; e = e.userInfo[NSUnderlyingErrorKey]) {
        if ([e.domain isEqualToString:NSCocoaErrorDomain] &&
            e.code == NSFileWriteUnknownError) {
            return YES;
        }
    }
    return NO;
}

/// Log every level of an error's underlying chain, so the next swap failure is
/// one glance at the activity log rather than a screenshot and a grep.
- (void)logSwapErrorChain:(NSError *)error bundleID:(NSString *)bundleID {
    NSInteger level = 0;
    for (NSError *e = error; e; e = e.userInfo[NSUnderlyingErrorKey], level++) {
        [self log:@"%@:   swap error [%ld] %@ %ld — %@",
            bundleID, (long)level, e.domain, (long)e.code, e.localizedDescription];
    }
}

/// The escalation path: register the helper if needed, then perform the swap as
/// root over XPC. Stays in CDRUpdatePhaseSwapping throughout. Registration is
/// lazy — the first time a swap actually needs it — never at launch.
- (void)escalateSwapForStagedApp:(NSURL *)stagedApp bundleID:(NSString *)bundleID {
    if (!self.helperManager.isHelperInstalled) {
        NSError *installError = nil;
        if (![self.helperManager installHelperWithError:&installError]) {
            // Includes SMAppServiceStatusRequiresApproval: the manager has already
            // opened System Settings › Login Items and handed back an actionable
            // error. Fail with it — do not block/poll for approval; the next
            // update attempt goes through the helper.
            [self log:@"%@: %@", bundleID, installError.localizedDescription];
            [self failWithError:installError];
            return;
        }
        [self log:@"%@: privileged helper registered.", bundleID];
    }

    [self log:@"%@: escalating to the privileged helper.", bundleID];

    // XPC delivers the completion on an arbitrary private queue; hop back onto
    // workQueue before touching the phase machine. Exactly one continuation may
    // run: the manager funnels its proxy-error and reply paths into a single
    // completion, but guard the async suspension anyway (the one-shot shape
    // CDRQuitMonitor uses) — the pipeline's usual return-after-terminal guarantee
    // does not cover a call that resumes on another queue.
    // (If privileged swaps fail here with a connection error in a Debug build,
    // suspect the helper's Team-ID/identifier pinning rejecting a differently
    // signed client before assuming the wiring is wrong.)
    __block BOOL finished = NO;
    [self.helperManager swapBundleAtURL:self.registration.appURL
                        withStagedAtURL:stagedApp
                             completion:^(BOOL success, NSURL *backupURL, NSError *swapError) {
        dispatch_async(self.workQueue, ^{
            if (finished) return;
            finished = YES;
            if (success) {
                [self log:@"%@: privileged swap succeeded.", bundleID];
                [self finishSwapWithBackupURL:backupURL bundleID:bundleID];
            } else {
                [self log:@"%@: privileged swap failed — %@", bundleID, swapError.localizedDescription];
                [self failWithError:swapError];
            }
        });
    }];
}

@end
