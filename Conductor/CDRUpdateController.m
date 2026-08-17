//
//  CDRUpdateController.m
//  Conductor
//

#import "CDRUpdateController.h"
#import <AppKit/AppKit.h>
#import "CDRAppScanner.h"
#import "CDRAppRegistration.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRUpdateOperation.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdateStateStore.h"
#import "CDRAppUpdateState.h"
#import "CDRErrors.h"
#import "CDRIgnoreList.h"
#import "CDRSharedLog.h"

BOOL CDRDecisionWarrantsNotification(CDRUpdateDecision *decision,
                                     CDRAppUpdateState *previousState,
                                     CDRManifest *manifest) {
    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable:
            // Quiet re-sightings of a version the user was already told about.
            return ![manifest.version isEqualToString:previousState.lastNotifiedVersion];
        case CDRUpdateOutcomeRetractedPending:
            return YES;
        default:
            return NO;
    }
}

@interface CDRUpdateController () <CDRUpdateOperationDelegate>
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) CDRAppScanner *scanner;
@property (nonatomic) CDRManifestFetcher *fetcher;
@property (nonatomic) CDRUpdateStateStore *stateStore;
@property (nonatomic) NSUserDefaults *defaults;

@property (nonatomic, readwrite, copy) NSArray<CDRAppRegistration *> *registrations;
@property (nonatomic, readwrite, copy) NSArray<CDRAppRowModel *> *rowModels;

/// bundleID → last fetched manifest that is installable right now (Available
/// or consented break-through). The gate installApp: checks.
@property (nonatomic) NSMutableDictionary<NSString *, CDRManifest *> *knownManifests;
@property (nonatomic) NSMutableDictionary<NSString *, CDRUpdateDecision *> *lastDecisions;
@property (nonatomic) NSMutableDictionary<NSString *, CDRManifest *> *lastManifests;
@property (nonatomic) NSMutableDictionary<NSString *, NSError *> *lastErrors;

@property (nonatomic) NSMutableDictionary<NSString *, CDRUpdateOperation *> *operations;
/// Phase mirror maintained from delegate callbacks so row building never reads
/// an operation's state across queues.
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *operationPhases;
/// Operations parked in update-on-quit (set when that reply is chosen).
@property (nonatomic) NSMutableSet<NSString *> *parkedBundleIDs;
/// bundleID → last reported download fraction, for the aggregate progress bar.
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *downloadFractions;
/// Whether an operation reached the download phase. Distinguishes the two
/// CDRErrorDowngradeRefused sources: the pre-download last-moment re-check (a
/// retraction — State A) vs the staged-bundle version gate (a replayed older
/// artifact — a plain refusal, no retraction messaging).
@property (nonatomic) NSMutableSet<NSString *> *reachedDownloadBundleIDs;
/// "bundleID|version" pairs whose State B notice was surfaced this launch
/// (re-shown once per launch, never a nag timer — roadmap M2 decision).
@property (nonatomic) NSMutableSet<NSString *> *notifiedRecalledKeys;
@end

@implementation CDRUpdateController

- (instancetype)initWithSession:(CDRDevModeSession *)session
                        scanner:(CDRAppScanner *)scanner
                        fetcher:(CDRManifestFetcher *)fetcher
                     stateStore:(CDRUpdateStateStore *)stateStore
                       defaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (!self) return nil;
    _session = session;
    _scanner = scanner;
    _fetcher = fetcher;
    _stateStore = stateStore;
    _defaults = defaults;
    _registrations = @[];
    _rowModels = @[];
    _knownManifests = [NSMutableDictionary dictionary];
    _lastDecisions = [NSMutableDictionary dictionary];
    _lastManifests = [NSMutableDictionary dictionary];
    _lastErrors = [NSMutableDictionary dictionary];
    _operations = [NSMutableDictionary dictionary];
    _operationPhases = [NSMutableDictionary dictionary];
    _parkedBundleIDs = [NSMutableSet set];
    _downloadFractions = [NSMutableDictionary dictionary];
    _reachedDownloadBundleIDs = [NSMutableSet set];
    _notifiedRecalledKeys = [NSMutableSet set];
    return self;
}

- (nullable CDRAppRegistration *)registrationForBundleID:(NSString *)bundleID {
    for (CDRAppRegistration *reg in self.registrations) {
        if ([reg.bundleID isEqualToString:bundleID]) return reg;
    }
    return nil;
}

/// Swaps the entry with a matching bundleID in registrations. No-op if absent
/// (app removed mid-session; the next rescan reconciles).
- (void)replaceRegistrationForBundleID:(NSString *)bundleID with:(CDRAppRegistration *)registration {
    NSUInteger idx = [self.registrations indexOfObjectPassingTest:
        ^BOOL(CDRAppRegistration *reg, NSUInteger i, BOOL *stop) {
            return [reg.bundleID isEqualToString:bundleID];
        }];
    if (idx == NSNotFound) return;
    NSMutableArray<CDRAppRegistration *> *updated = [self.registrations mutableCopy];
    updated[idx] = registration;
    self.registrations = updated;
}

#pragma mark - Discovery

- (void)rescan {
    NSArray<CDRAppRegistration *> *all = [self.scanner scanApplicationsDirectory];
    NSMutableArray<CDRAppRegistration *> *visible = [NSMutableArray array];
    for (CDRAppRegistration *reg in all) {
        if ([self.session isBundleVisible:reg.bundleID]) [visible addObject:reg];
    }
    self.registrations = visible;
    [CDRSharedLog log:[NSString stringWithFormat:@"Scan: %lu managed app(s) found.",
                       (unsigned long)visible.count]];
    [self rebuildRowModels];
}

#pragma mark - Checks

- (void)checkAllPassive {
    NSSet<NSString *> *ignored = CDRIgnoredBundleIDs(self.defaults);
    for (CDRAppRegistration *reg in self.registrations) {
        if ([ignored containsObject:reg.bundleID]) continue;
        [self checkRegistration:reg breakThrough:NO];
    }
}

- (void)checkApp:(NSString *)bundleID userInitiated:(BOOL)userInitiated {
    CDRAppRegistration *reg = [self registrationForBundleID:bundleID];
    if (!reg) return;
    [self checkRegistration:reg breakThrough:userInitiated];
}

- (void)checkRegistration:(CDRAppRegistration *)reg breakThrough:(BOOL)breakThrough {
    // The installed version is ephemeral: the bundle may have been replaced
    // since the last scan (by Conductor itself or out-of-band), so re-read it
    // from disk before every check — one plist read, no discovery churn.
    CDRAppRegistration *fresh = [reg registrationByRefreshingInstalledVersion];
    if (fresh != reg) {
        [self replaceRegistrationForBundleID:fresh.bundleID with:fresh];
        [self rebuildRowModels];   // the Installed column corrects even if the fetch then fails
        reg = fresh;
    }
    NSString *bundleID = reg.bundleID;
    [CDRSharedLog log:[NSString stringWithFormat:@"%@: fetching manifest from %@ …",
                       bundleID, reg.updateURL.absoluteString]];

    __weak typeof(self) weakSelf = self;
    [self.fetcher fetchManifestForRegistration:reg completion:^(CDRManifest *manifest, NSError *error) {
        // The fetcher completes on an arbitrary queue; decide and present on
        // main (state mutations, presentation).
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (!manifest) {
                self.lastErrors[bundleID] = error;
                [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
                [self logVendorEscapeHatch:error.userInfo[CDRErrorVendorURLKey] forBundleID:bundleID];
                [self rebuildRowModels];
                return;
            }

            [self.lastErrors removeObjectForKey:bundleID];
            NSDate *now = [NSDate date];
            CDRSoakDuration soak = CDRSoakDurationFromDefaultsToken(
                [self.defaults stringForKey:CDRSoakDurationDefaultsKey]);
            CDRAppUpdateState *previousState = [self.stateStore stateForBundleID:bundleID];
            CDRUpdateDecision *decision = [CDRUpdatePolicy decisionForRegistration:reg
                                                                          manifest:manifest
                                                                             state:previousState
                                                                      soakDuration:soak
                                                                      breakThrough:breakThrough
                                                                               now:now];
            [self.stateStore putState:decision.stateAfterCheck];
            self.lastDecisions[bundleID] = decision;
            self.lastManifests[bundleID] = manifest;
            [self handleDecision:decision manifest:manifest registration:reg previousState:previousState];
            [self rebuildRowModels];
        });
    }];
}

- (void)handleDecision:(CDRUpdateDecision *)decision
              manifest:(CDRManifest *)manifest
          registration:(CDRAppRegistration *)reg
         previousState:(nullable CDRAppUpdateState *)previousState {
    NSString *bundleID = reg.bundleID;
    NSString *appName = reg.appURL.lastPathComponent.stringByDeletingPathExtension;

    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable: {
            self.knownManifests[bundleID] = manifest;
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: update %@ available (installed: %@).",
                               bundleID, manifest.version, reg.installedShortVersion]];
            if (decision.urgency != CDRUrgencyNone) {
                [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID,
                                   CDRUrgencyNoticeCopy(decision.urgency, appName, manifest.version)]];
            }
            if (CDRDecisionWarrantsNotification(decision, previousState, manifest)) {
                [self.presenter notifyUpdateAvailableForAppNamed:appName
                                                        bundleID:bundleID
                                                         version:manifest.version
                                                         urgency:decision.urgency];
            }
            break;
        }

        case CDRUpdateOutcomeDeferred: {
            // Hidden while deferred: Install must not be reachable.
            [self.knownManifests removeObjectForKey:bundleID];
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateStyle = NSDateFormatterMediumStyle;
            fmt.timeStyle = NSDateFormatterNoStyle;
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@ is deferred until %@ by the update settings.",
                               bundleID, manifest.version, [fmt stringFromDate:decision.deferredUntil]]];
            break;
        }

        case CDRUpdateOutcomeDeferredOffered: {
            __weak typeof(self) weakSelf = self;
            [self.presenter presentDeferredOfferForAppNamed:appName
                                                    version:manifest.version
                                              deferredUntil:decision.deferredUntil
                                                 completion:^(BOOL installAnyway) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                if (installAnyway) {
                    // Consent marks it notified — retraction loudness now
                    // applies to this version like any surfaced update.
                    [self.stateStore noteNotifiedVersion:manifest.version build:manifest.build
                                             forBundleID:bundleID at:[NSDate date]];
                    self.knownManifests[bundleID] = manifest;
                    [self installApp:bundleID];
                } else {
                    [self.knownManifests removeObjectForKey:bundleID];
                }
                [self rebuildRowModels];
            }];
            break;
        }

        case CDRUpdateOutcomeRetractedPending: {
            // State A during a check: loud once (the decision already cleared
            // the notified memory), passively — never a modal here.
            [self.knownManifests removeObjectForKey:bundleID];
            NSString *message = CDRRetractedPendingCopy(appName, decision.retractedVersion,
                                                        reg.installedShortVersion);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, message]];
            [self.presenter notifyRetractedPending:message bundleID:bundleID vendorURL:reg.vendorURL];
            break;
        }

        case CDRUpdateOutcomeRetractedInstalled: {
            // State B: inform, never auto-downgrade; re-shown once per launch.
            [self.knownManifests removeObjectForKey:bundleID];
            NSString *message = CDRRetractedInstalledCopy(appName, decision.retractedVersion);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, message]];
            NSString *key = [NSString stringWithFormat:@"%@|%@", bundleID, decision.retractedVersion];
            if (![self.notifiedRecalledKeys containsObject:key]) {
                [self.notifiedRecalledKeys addObject:key];
                [self.presenter notifyRetractedInstalled:message bundleID:bundleID vendorURL:reg.vendorURL];
            }
            break;
        }

        case CDRUpdateOutcomeUpToDate:
        case CDRUpdateOutcomeDroppedSilently: {
            // Identical presentation by design: a never-surfaced version that
            // vanished owes the user nothing (retraction.md).
            [self.knownManifests removeObjectForKey:bundleID];
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: up to date (%@).",
                               bundleID, reg.installedShortVersion]];
            break;
        }
    }
}

#pragma mark - Install

- (void)installApp:(NSString *)bundleID {
    CDRAppRegistration *reg = [self registrationForBundleID:bundleID];
    if (!reg) return;
    if (self.operations[bundleID]) {
        [CDRSharedLog log:[NSString stringWithFormat:@"%@: an update is already in progress.", bundleID]];
        return;
    }
    CDRManifest *manifest = self.knownManifests[bundleID];
    if (!manifest) {
        [CDRSharedLog log:[NSString stringWithFormat:@"%@: no known update — run Check first.", bundleID]];
        return;
    }

    CDRUpdateOperation *op = [[CDRUpdateOperation alloc] initWithRegistration:reg
                                                                     manifest:manifest
                                                                      session:self.session
                                                                     delegate:self];
    self.operations[bundleID] = op;
    self.operationPhases[bundleID] = @(CDRUpdatePhaseIdle);
    [self.reachedDownloadBundleIDs removeObject:bundleID];
    [self.parkedBundleIDs removeObject:bundleID];
    [op start];
    [self rebuildRowModels];
}

#pragma mark - Row actions

- (void)performRowAction:(CDRAppRowActions)action forBundleID:(NSString *)bundleID {
    switch (action) {
        case CDRAppRowActionInstall:
            [self installApp:bundleID];
            break;
        case CDRAppRowActionCheckNow:
            [self checkApp:bundleID userInitiated:YES];
            break;
        case CDRAppRowActionIgnore:
            CDRSetBundleIDIgnored(bundleID, YES, self.defaults);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: ignored — excluded from scheduled checks.", bundleID]];
            [self rebuildRowModels];
            break;
        case CDRAppRowActionUnignore:
            CDRSetBundleIDIgnored(bundleID, NO, self.defaults);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: no longer ignored.", bundleID]];
            [self rebuildRowModels];
            break;
        case CDRAppRowActionVendorSite: {
            NSURL *url = [self vendorURLForBundleID:bundleID];
            if (url) [[NSWorkspace sharedWorkspace] openURL:url];
            break;
        }
        case CDRAppRowActionCancelPending:
            [self.operations[bundleID] cancelParkedUpdate];
            break;
        default:
            break;
    }
}

- (nullable NSURL *)vendorURLForBundleID:(NSString *)bundleID {
    NSError *error = self.lastErrors[bundleID];
    NSURL *fromError = error.userInfo[CDRErrorVendorURLKey];
    return fromError ?: [self registrationForBundleID:bundleID].vendorURL;
}

- (BOOL)hasOperationsInCriticalPhase {
    for (NSString *bundleID in self.operationPhases) {
        CDRUpdatePhase phase = self.operationPhases[bundleID].integerValue;
        switch (phase) {
            case CDRUpdatePhaseDownloading:
            case CDRUpdatePhaseExtracting:
            case CDRUpdatePhaseVerifying:
            case CDRUpdatePhaseSwapping:
            case CDRUpdatePhaseFinishing:
                return YES;
            default:
                break;
        }
    }
    return NO;
}

#pragma mark - CDRUpdateOperationDelegate (main queue)

- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase {
    NSString *bundleID = op.registration.bundleID;
    self.operationPhases[bundleID] = @(phase);
    if (phase == CDRUpdatePhaseDownloading) [self.reachedDownloadBundleIDs addObject:bundleID];
    if (phase != CDRUpdatePhaseDownloading) [self.downloadFractions removeObjectForKey:bundleID];
    // A parked wait ends the moment the swap begins.
    if (phase == CDRUpdatePhaseSwapping) [self.parkedBundleIDs removeObject:bundleID];
    [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@ …", bundleID, CDRUpdatePhaseName(phase)]];
    [self rebuildRowModels];
    [self publishProgress];
}

- (void)updateOperation:(CDRUpdateOperation *)op didUpdateDownloadProgress:(double)fractionCompleted {
    self.downloadFractions[op.registration.bundleID] = @(fractionCompleted);
    [self publishProgress];
}

/// Folds every live operation into one bar: determinate (mean fraction) while
/// anything is downloading, indeterminate while otherwise busy, inactive when
/// idle. Parked update-on-quit waits are excluded — they can sit for days.
- (void)publishProgress {
    if (!self.onProgressChanged) return;
    NSMutableArray<NSString *> *active = [NSMutableArray array];
    NSMutableArray<NSString *> *downloading = [NSMutableArray array];
    CDRUpdatePhase lastPhase = CDRUpdatePhaseIdle;
    for (NSString *bundleID in self.operationPhases) {
        CDRUpdatePhase phase = self.operationPhases[bundleID].integerValue;
        if (phase < CDRUpdatePhaseFetching || phase > CDRUpdatePhaseFinishing) continue;
        if ([self.parkedBundleIDs containsObject:bundleID]) continue;
        [active addObject:bundleID];
        lastPhase = phase;
        if (phase == CDRUpdatePhaseDownloading) [downloading addObject:bundleID];
    }
    if (active.count == 0) {
        self.onProgressChanged(NO, 0, nil);
        return;
    }
    if (downloading.count > 0) {
        double sum = 0;
        for (NSString *bundleID in downloading) sum += self.downloadFractions[bundleID].doubleValue;
        double fraction = sum / downloading.count;
        NSString *detail = (downloading.count == 1)
            ? [NSString stringWithFormat:@"Downloading %@ — %.0f%%",
               [self displayNameForBundleID:downloading.firstObject], fraction * 100]
            : [NSString stringWithFormat:@"Downloading %lu updates — %.0f%%",
               (unsigned long)downloading.count, fraction * 100];
        self.onProgressChanged(YES, fraction, detail);
        return;
    }
    NSString *detail = (active.count == 1)
        ? [NSString stringWithFormat:@"%@ — %@…",
           [self displayNameForBundleID:active.firstObject], CDRUpdatePhaseName(lastPhase)]
        : [NSString stringWithFormat:@"Updating %lu apps…", (unsigned long)active.count];
    self.onProgressChanged(YES, -1, detail);
}

- (NSString *)displayNameForBundleID:(NSString *)bundleID {
    NSString *name = [self registrationForBundleID:bundleID]
        .appURL.lastPathComponent.stringByDeletingPathExtension;
    return name ?: bundleID;
}

- (void)updateOperation:(CDRUpdateOperation *)op logMessage:(NSString *)message {
    [CDRSharedLog log:message];
}

- (void)updateOperation:(CDRUpdateOperation *)op
    requestsQuitDecisionFor:(NSArray<NSRunningApplication *> *)runningApps
                      reply:(void (^)(CDRQuitDecision))reply {
    NSString *bundleID = op.registration.bundleID;
    NSString *appName = op.registration.appURL.lastPathComponent.stringByDeletingPathExtension;
    __weak typeof(self) weakSelf = self;
    [self.presenter presentQuitDecisionForAppNamed:appName reply:^(CDRQuitDecision decision) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self && decision == CDRQuitDecisionUpdateOnQuit) {
            [self.parkedBundleIDs addObject:bundleID];
            [self rebuildRowModels];
        }
        reply(decision);
    }];
}

- (void)updateOperation:(CDRUpdateOperation *)op
     didFinishWithError:(NSError *)error
       appWasQuitByFlow:(BOOL)wasQuit {
    NSString *bundleID = op.registration.bundleID;
    NSString *appName = op.registration.appURL.lastPathComponent.stringByDeletingPathExtension;
    [self.operations removeObjectForKey:bundleID];
    [self.operationPhases removeObjectForKey:bundleID];
    [self.parkedBundleIDs removeObject:bundleID];
    [self.downloadFractions removeObjectForKey:bundleID];
    [self publishProgress];

    if (error) {
        if ([error.domain isEqualToString:CDRErrorDomain] && error.code == CDRErrorUpdateCancelled) {
            // User-requested cancellation of a parked update: informational.
            // The known manifest survives so Install works without re-checking.
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
            [self rebuildRowModels];
            return;
        }
        if ([error.domain isEqualToString:CDRErrorDomain] && error.code == CDRErrorDowngradeRefused
            && ![self.reachedDownloadBundleIDs containsObject:bundleID]) {
            // The operation's last-moment manifest re-check caught a
            // retraction between notify and install (retraction.md) — this is
            // State A, not a generic failure. The operation stays state-free;
            // the state reaction lives here.
            [self.stateStore clearNotifiedVersionForBundleID:bundleID at:[NSDate date]];
            [self.knownManifests removeObjectForKey:bundleID];
            [self.lastDecisions removeObjectForKey:bundleID];
            [self.lastManifests removeObjectForKey:bundleID];
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
            [self.presenter presentRetractionNotice:error.localizedDescription
                                          vendorURL:(error.userInfo[CDRErrorVendorURLKey]
                                                     ?: op.registration.vendorURL)];
            [self rebuildRowModels];
            return;
        }
        NSMutableString *msg = [NSMutableString stringWithFormat:@"%@: FAILED — %@", bundleID, error.localizedDescription];
        for (NSError *e = error.userInfo[NSUnderlyingErrorKey]; e; e = e.userInfo[NSUnderlyingErrorKey]) {
            [msg appendFormat:@"\n    ↳ %@ (%@ %ld)", e.localizedDescription, e.domain, (long)e.code];
        }
        [CDRSharedLog log:msg];
        [self logVendorEscapeHatch:error.userInfo[CDRErrorVendorURLKey] forBundleID:bundleID];
        self.lastErrors[bundleID] = error;
        [self.presenter notifyInstallFailedForAppNamed:appName bundleID:bundleID error:error
                                             vendorURL:(error.userInfo[CDRErrorVendorURLKey]
                                                        ?: op.registration.vendorURL)];
        [self rebuildRowModels];
        return;
    }

    [CDRSharedLog log:[NSString stringWithFormat:@"%@: update installed successfully.", bundleID]];
    // Push the just-installed version into the registration immediately — the
    // staged bundle's Info.plist is the authority, never the manifest (which
    // only serves as fallback copy for the notification when Verify's capture
    // is somehow absent).
    NSString *installedVersion = op.stagedShortVersion ?: self.knownManifests[bundleID].version;
    if (op.stagedShortVersion) {
        [self replaceRegistrationForBundleID:bundleID
            with:[op.registration registrationWithInstalledShortVersion:op.stagedShortVersion
                                                           buildVersion:op.stagedBuildVersion]];
    }
    [self.knownManifests removeObjectForKey:bundleID];
    [self.lastDecisions removeObjectForKey:bundleID];
    [self.lastManifests removeObjectForKey:bundleID];
    [self.lastErrors removeObjectForKey:bundleID];
    [self rescan];
    [self.presenter notifyInstallCompletedForAppNamed:appName bundleID:bundleID version:installedVersion];

    if (wasQuit) {
        [self.presenter presentRelaunchOfferForAppNamed:appName appURL:op.registration.appURL];
    }
}

#pragma mark - Row models

- (void)logVendorEscapeHatch:(nullable NSURL *)vendorURL forBundleID:(NSString *)bundleID {
    if (!vendorURL) return;
    [CDRSharedLog log:[NSString stringWithFormat:@"%@: check the developer's site: %@",
                       bundleID, vendorURL.absoluteString]];
}

- (void)rebuildRowModels {
    NSSet<NSString *> *ignored = CDRIgnoredBundleIDs(self.defaults);
    NSMutableArray<CDRAppRowModel *> *rows = [NSMutableArray arrayWithCapacity:self.registrations.count];
    for (CDRAppRegistration *reg in self.registrations) {
        NSString *bundleID = reg.bundleID;
        CDRUpdatePhase phase = self.operationPhases[bundleID]
            ? self.operationPhases[bundleID].integerValue : CDRUpdatePhaseIdle;
        [rows addObject:[CDRAppRowModel modelForRegistration:reg
                                                lastDecision:self.lastDecisions[bundleID]
                                             decidedManifest:self.lastManifests[bundleID]
                                                   lastError:self.lastErrors[bundleID]
                                                     ignored:[ignored containsObject:bundleID]
                                              operationPhase:phase
                                                      parked:[self.parkedBundleIDs containsObject:bundleID]]];
    }
    self.rowModels = rows;
    if (self.onRowModelsChanged) self.onRowModelsChanged();
}

@end
