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

@property (nonatomic, nullable) NSURL *stagingURL;
@property (nonatomic, nullable) NSString *pinnedTeamID;
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
    [self.downloader downloadArtifactAtURL:self.manifest.artifactURL
                               forBundleID:self.registration.bundleID
                        toStagingDirectory:self.stagingURL
                            expectedSHA256:self.manifest.sha256
                                  progress:nil
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
    NSBundle *staged = [NSBundle bundleWithURL:stagedApp];
    NSString *stagedBundleID = staged.bundleIdentifier;
    if (![stagedBundleID isEqualToString:bundleID]) {
        [self failWithError:CDRError(CDRErrorBundleIDMismatch, bundleID, nil, nil)];
        return;
    }

    // 3.2 Version sanity — from the staged Info.plist, never the manifest.
    // Load-bearing against replay of an older validly-signed build.
    NSString *stagedShort = [staged objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *stagedBuild = [staged objectForInfoDictionaryKey:@"CFBundleVersion"];
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
        [delegate updateOperation:self requestsQuitDecisionFor:running reply:^(BOOL quitAndContinue) {
            if (!quitAndContinue) {
                dispatch_async(self.workQueue, ^{
                    [self failWithError:CDRError(CDRErrorUserDeclinedQuit, bundleID, nil, nil)];
                });
                return;
            }
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
        }];
    });
}

/// §5 — the single mutation of /Applications.
- (void)stepSwap:(NSURL *)stagedApp {
    [self enterPhase:CDRUpdatePhaseSwapping];
    NSString *bundleID = self.registration.bundleID;

    NSURL *backup = nil;
    NSError *error = nil;
    BOOL ok = [self.swapper swapInstalledAppAtURL:self.registration.appURL
                               withStagedAppAtURL:stagedApp
                                         bundleID:bundleID
                                        backupURL:&backup
                                            error:&error];
    if (!ok) {
        [self failWithError:error];
        return;
    }
    [self log:@"%@: swapped in new bundle.", bundleID];

    [self enterPhase:CDRUpdatePhaseFinishing];

    // Displaced bundle → Trash. Non-fatal: on failure it merely lingers.
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

@end
