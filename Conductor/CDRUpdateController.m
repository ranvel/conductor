//
//  CDRUpdateController.m
//  Conductor
//

#import "CDRUpdateController.h"
#import <AppKit/AppKit.h>
#import "CDRAppScanner.h"
#import "CDRAppRegistration.h"
#import "CDRBundleInspector.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRUpdateOperation.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdatePreferences.h"
#import "CDRUpdateStateStore.h"
#import "CDRAppUpdateState.h"
#import "CDRErrors.h"
#import "CDRIgnoreList.h"
#import "CDRRetractionNotices.h"
#import "CDRNetworkInspection.h"
#import "CDRInternetAccessPolicy.h"
#import "CDRSharedLog.h"

BOOL CDRDecisionWarrantsNotification(CDRUpdateDecision *decision,
                                     CDRAppUpdateState *previousState,
                                     CDRManifest *manifest) {
    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable:
        case CDRUpdateOutcomeHeld:
        case CDRUpdateOutcomeStoppedAtMajor:
            // Quiet re-sightings of a version the user was already told about.
            return ![manifest.version isEqualToString:previousState.lastNotifiedVersion];
        case CDRUpdateOutcomeRetractedPending:
            return YES;
        default:
            return NO;
    }
}

/// What the installed copy of an app may do on the network, read once per
/// (path, version) — display and consent data only.
@interface CDRInstalledNetworkInfo : NSObject
@property (nonatomic) CDRNetworkPosture posture;
@property (nonatomic, nullable) CDRInternetAccessPolicy *policy;
@property (nonatomic, copy) NSArray<NSString *> *entitlementKeys;
@property (nonatomic, copy, nullable) NSString *teamID;
@end

@implementation CDRInstalledNetworkInfo
@end

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
/// appURL path → signing organization, read once per bundle path (display
/// only). NSNull marks "looked, found nothing" so unsigned apps aren't re-read.
@property (nonatomic) NSMutableDictionary<NSString *, id> *developerNames;
@property (nonatomic, readwrite, nullable) NSDate *lastCheckDate;

// Network gate (CND-7)
/// "path|version" → what the installed build may do on the network.
@property (nonatomic) NSMutableDictionary<NSString *, CDRInstalledNetworkInfo *> *installedNetwork;
/// Operations Conductor started on its own, to inspect a new build before
/// the user is asked anything. They never get past the approval park
/// without a click, and their failures are quiet.
@property (nonatomic) NSMutableSet<NSString *> *inspectingBundleIDs;
/// Inspect-ahead operations whose update was superseded or withdrawn while
/// they ran: declined the moment they reach the approval step.
@property (nonatomic) NSMutableSet<NSString *> *supersededBundleIDs;
/// bundleID → the parked operation's reply block, while it waits for approval.
@property (nonatomic) NSMutableDictionary<NSString *, void (^)(BOOL)> *pendingApprovals;
/// bundleID → what the parked (or running) operation learned.
@property (nonatomic) NSMutableDictionary<NSString *, CDRNetworkInspection *> *inspections;
/// bundleID → the version whose inspect-ahead failed, so it isn't retried
/// on every check.
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *failedInspectionVersions;
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
    _developerNames = [NSMutableDictionary dictionary];
    _installedNetwork = [NSMutableDictionary dictionary];
    _inspectingBundleIDs = [NSMutableSet set];
    _supersededBundleIDs = [NSMutableSet set];
    _pendingApprovals = [NSMutableDictionary dictionary];
    _inspections = [NSMutableDictionary dictionary];
    _failedInspectionVersions = [NSMutableDictionary dictionary];
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

/// A Settings value or a per-app override changed. Every app with an update
/// pending is decided again from the manifest already in hand, so removing a
/// hold category, switching off the major stop or changing a deferral takes
/// effect now rather than at the next check. Nothing is fetched and nothing
/// is notified. Retraction notices are left alone: their decision was
/// one-time and re-deciding would erase a notice the user hasn't read.
- (void)preferencesDidChange {
    for (CDRAppRegistration *reg in self.registrations) {
        NSString *bundleID = reg.bundleID;
        CDRManifest *manifest = self.lastManifests[bundleID];
        CDRUpdateDecision *last = self.lastDecisions[bundleID];
        if (!manifest || !last || self.operations[bundleID]) continue;
        switch (last.outcome) {
            case CDRUpdateOutcomeAvailable:
            case CDRUpdateOutcomeDeferred:
            case CDRUpdateOutcomeDeferredOffered:
            case CDRUpdateOutcomeHeld:
            case CDRUpdateOutcomeStoppedAtMajor:
                [self evaluateManifest:manifest registration:reg breakThrough:NO notify:NO];
                break;
            default:
                break;
        }
    }
    [self rebuildRowModels];
}

#pragma mark - Checks

- (void)checkAllPassive {
    [self checkAllUserStarted:NO];
}

- (void)checkAllUserStarted {
    [self checkAllUserStarted:YES];
}

- (void)checkAllUserStarted:(BOOL)userStarted {
    NSSet<NSString *> *ignored = CDRIgnoredBundleIDs(self.defaults);
    for (CDRAppRegistration *reg in self.registrations) {
        if ([ignored containsObject:reg.bundleID]) continue;
        [self checkRegistration:reg breakThrough:NO userStarted:userStarted];
    }
}

- (void)checkApp:(NSString *)bundleID userInitiated:(BOOL)userInitiated {
    CDRAppRegistration *reg = [self registrationForBundleID:bundleID];
    if (!reg) return;
    [self checkRegistration:reg breakThrough:userInitiated userStarted:userInitiated];
}

- (void)checkRegistration:(CDRAppRegistration *)reg breakThrough:(BOOL)breakThrough userStarted:(BOOL)userStarted {
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
            self.lastCheckDate = [NSDate date];
            // Release notes are display data: anything the parser dropped is
            // said here, once per check, and changes nothing else.
            for (NSString *warning in manifest.parseWarnings) {
                [CDRSharedLog log:[NSString stringWithFormat:@"%@: manifest — %@", bundleID, warning]];
            }
            [self evaluateManifest:manifest registration:reg breakThrough:breakThrough
                       userStarted:userStarted notify:YES];
            [self rebuildRowModels];
        });
    }];
}

/// Runs the policy for one app against a manifest, with the preferences
/// resolved for *that app* (Settings with its override applied), persists the
/// resulting memory and reacts to the decision. `notify` is NO when nothing
/// new was fetched — a preference change re-deciding the manifest already in
/// hand must not post a notification about it.
- (CDRUpdateDecision *)evaluateManifest:(CDRManifest *)manifest
                           registration:(CDRAppRegistration *)reg
                           breakThrough:(BOOL)breakThrough
                                 notify:(BOOL)notify {
    return [self evaluateManifest:manifest registration:reg breakThrough:breakThrough
                      userStarted:breakThrough notify:notify];
}

/// `userStarted` says the check behind this manifest was one the user asked
/// for. Only then may a finding be *presented* (a sheet) rather than
/// notified — a scheduled check never raises anything modal.
- (CDRUpdateDecision *)evaluateManifest:(CDRManifest *)manifest
                           registration:(CDRAppRegistration *)reg
                           breakThrough:(BOOL)breakThrough
                            userStarted:(BOOL)userStarted
                                 notify:(BOOL)notify {
    NSString *bundleID = reg.bundleID;
    CDRUpdatePreferences *preferences =
        [CDRPolicyResolver effectivePreferencesForBundleID:bundleID defaults:self.defaults];
    CDRAppUpdateState *previousState = [self.stateStore stateForBundleID:bundleID];
    CDRUpdateDecision *decision = [CDRUpdatePolicy decisionForRegistration:reg
                                                                  manifest:manifest
                                                                     state:previousState
                                                               preferences:preferences
                                                              breakThrough:breakThrough
                                                                       now:[NSDate date]];
    [self.stateStore putState:decision.stateAfterCheck];
    self.lastDecisions[bundleID] = decision;
    self.lastManifests[bundleID] = manifest;
    [self handleDecision:decision manifest:manifest registration:reg
           previousState:previousState userStarted:userStarted notify:notify];
    return decision;
}

- (void)handleDecision:(CDRUpdateDecision *)decision
              manifest:(CDRManifest *)manifest
          registration:(CDRAppRegistration *)reg
         previousState:(nullable CDRAppUpdateState *)previousState
           userStarted:(BOOL)userStarted
                notify:(BOOL)notify {
    NSString *bundleID = reg.bundleID;
    NSString *appName = reg.appURL.lastPathComponent.stringByDeletingPathExtension;

    // An inspect-ahead operation is only wanted while the same version is
    // still plainly available. Anything else — a newer version, a retraction,
    // a hold — and it is discarded: now if it is parked, or as soon as it
    // reaches the approval step if it is still running.
    CDRUpdateOperation *running = self.operations[bundleID];
    if (running && [self.inspectingBundleIDs containsObject:bundleID]) {
        BOOL stillWanted = decision.outcome == CDRUpdateOutcomeAvailable
            && [running.manifestVersion isEqualToString:manifest.version];
        if (!stillWanted) {
            if (self.pendingApprovals[bundleID]) [self resolveApproval:NO forBundleID:bundleID];
            else [self.supersededBundleIDs addObject:bundleID];
        }
    }

    // A retraction notice is about a version that was pulled with nothing
    // newer on offer. Once the developer advertises something newer again,
    // or the recalled build turns out to be installed, it is moot.
    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable:
        case CDRUpdateOutcomeDeferred:
        case CDRUpdateOutcomeDeferredOffered:
        case CDRUpdateOutcomeHeld:
        case CDRUpdateOutcomeStoppedAtMajor:
        case CDRUpdateOutcomeRetractedInstalled:
            CDRSetRetractionNotice(nil, bundleID, self.defaults);
            break;
        default:
            break;
    }

    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable: {
            self.knownManifests[bundleID] = manifest;
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: update %@ available (installed: %@).",
                               bundleID, manifest.version, reg.installedShortVersion]];
            if (decision.urgency != CDRUrgencyNone) {
                [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID,
                                   CDRUrgencyNoticeCopy(decision.urgency, appName, manifest.version)]];
            }
            if (notify && CDRDecisionWarrantsNotification(decision, previousState, manifest)) {
                [self.presenter notifyUpdateAvailableForAppNamed:appName
                                                        bundleID:bundleID
                                                         version:manifest.version
                                                         urgency:decision.urgency];
            }
            [self beginInspectionIfNeededForRegistration:reg manifest:manifest];
            break;
        }

        case CDRUpdateOutcomeSkipped: {
            [self.knownManifests removeObjectForKey:bundleID];
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@ was skipped at your request.",
                               bundleID, manifest.version]];
            break;
        }

        case CDRUpdateOutcomeHeld:
        case CDRUpdateOutcomeStoppedAtMajor: {
            // Surfaced and installable — on a deliberate click only. The
            // manifest is kept so that click works; nothing installs itself.
            self.knownManifests[bundleID] = manifest;
            NSString *reason = CDRUpdateGateReasonCopy(decision, reg.installedShortVersion, manifest.version);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: update %@ is waiting for you — %@",
                               bundleID, manifest.version, reason]];
            if (notify && CDRDecisionWarrantsNotification(decision, previousState, manifest)) {
                [self.presenter notifyUpdateNeedsAttentionForAppNamed:appName
                                                             bundleID:bundleID
                                                              version:manifest.version
                                                               reason:reason];
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
            // The decision is one-time; the notice is what keeps the row's
            // banner up until the user has read it.
            CDRSetRetractionNotice([CDRRetractionNotice noticeWithVersion:decision.retractedVersion
                                                              advertisedAt:previousState.notifiedAt
                                                                  pulledAt:[NSDate date]],
                                   bundleID, self.defaults);
            if (!notify) break;
            if (userStarted) {
                // The user asked for this check: the sheet if the window is
                // key, the notification otherwise (the presenter decides).
                __weak typeof(self) weakSelf = self;
                [self.presenter presentRetractionForAppNamed:appName
                                                    bundleID:bundleID
                                                      appURL:reg.appURL
                                            retractedVersion:decision.retractedVersion
                                            installedVersion:reg.installedShortVersion
                                                     message:message
                                                   vendorURL:reg.vendorURL
                                                  completion:^(BOOL acknowledged) {
                    if (acknowledged) [weakSelf performRowAction:CDRAppRowActionAcknowledge forBundleID:bundleID];
                }];
            } else {
                // A scheduled check never raises anything modal.
                [self.presenter notifyRetractedPending:message bundleID:bundleID vendorURL:reg.vendorURL];
            }
            break;
        }

        case CDRUpdateOutcomeRetractedInstalled: {
            // State B: inform, never auto-downgrade; re-shown once per launch.
            [self.knownManifests removeObjectForKey:bundleID];
            NSString *message = CDRRetractedInstalledCopy(appName, decision.retractedVersion);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, message]];
            NSString *key = [NSString stringWithFormat:@"%@|%@", bundleID, decision.retractedVersion];
            if (notify && ![self.notifiedRecalledKeys containsObject:key]) {
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
        if ([self.inspectingBundleIDs containsObject:bundleID]) {
            // Conductor was already fetching this build to inspect it. The
            // user wants it: from here on it is their install.
            [self.inspectingBundleIDs removeObject:bundleID];
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: continuing the build already being inspected.", bundleID]];
            if (self.pendingApprovals[bundleID]) [self continueParkedInstallForBundleID:bundleID];
            [self rebuildRowModels];
            return;
        }
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

#pragma mark - Network gate

- (CDRInstalledNetworkInfo *)installedNetworkInfoForRegistration:(CDRAppRegistration *)reg {
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", reg.appURL.path, reg.installedShortVersion,
                     reg.installedBuildVersion ?: @"-"];
    CDRInstalledNetworkInfo *info = self.installedNetwork[key];
    if (info) return info;

    info = [[CDRInstalledNetworkInfo alloc] init];
    NSString *team = nil;
    NSDictionary *entitlements = [CDRBundleInspector entitlementsForBundleAtURL:reg.appURL teamID:&team];
    info.posture = entitlements ? CDRNetworkPostureFromEntitlements(entitlements) : CDRNetworkPostureUnknown;
    info.teamID = team;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *entitlement in @[CDREntitlementAppSandbox, CDREntitlementNetworkClient, CDREntitlementNetworkServer]) {
        id value = entitlements[entitlement];
        if ([value isKindOfClass:[NSNumber class]] && [value boolValue]) [keys addObject:entitlement];
    }
    info.entitlementKeys = keys;
    // The installed copy's own policy, for the NETWORK row. Display only.
    info.policy = [CDRInternetAccessPolicy policyForBundleAtURL:reg.appURL];
    self.installedNetwork[key] = info;
    return info;
}

/// Starts an operation whose only purpose (so far) is to learn what the new
/// build may do on the network, so the row can say "Approve network access"
/// before the user has clicked anything. It runs the ordinary pipeline —
/// download, the whole of Verify, then Inspect — and parks there. It never
/// reaches the quit check or the swap without a click.
///
/// Only when it can matter: the gate is on, and the installed build provably
/// (or possibly) has no network access. A build that already has access
/// can't "gain" it, so nothing is downloaded ahead of time for those.
- (void)beginInspectionIfNeededForRegistration:(CDRAppRegistration *)reg manifest:(CDRManifest *)manifest {
    NSString *bundleID = reg.bundleID;
    if (self.operations[bundleID]) return;
    if ([self.failedInspectionVersions[bundleID] isEqualToString:manifest.version]) return;
    CDRUpdatePreferences *preferences =
        [CDRPolicyResolver effectivePreferencesForBundleID:bundleID defaults:self.defaults];
    if (!preferences.requireNetworkApproval) return;
    if (CDRNetworkPostureHasAccess([self installedNetworkInfoForRegistration:reg].posture)) return;

    [CDRSharedLog log:[NSString stringWithFormat:@"%@: downloading %@ to inspect its network access before you’re asked to install it.",
                       bundleID, manifest.version]];
    [self.inspectingBundleIDs addObject:bundleID];
    [self.supersededBundleIDs removeObject:bundleID];
    CDRUpdateOperation *op = [[CDRUpdateOperation alloc] initWithRegistration:reg
                                                                     manifest:manifest
                                                                      session:self.session
                                                                     delegate:self];
    self.operations[bundleID] = op;
    self.operationPhases[bundleID] = @(CDRUpdatePhaseIdle);
    [self.reachedDownloadBundleIDs removeObject:bundleID];
    [op start];
}

- (CDRNetworkGateDecision)gateDecisionForBundleID:(NSString *)bundleID {
    CDRNetworkInspection *inspection = self.inspections[bundleID];
    if (!inspection) return CDRNetworkGateDecisionNoAsk;
    return [CDRNetworkGate decisionForInspection:inspection
                                     preferences:[CDRPolicyResolver effectivePreferencesForBundleID:bundleID
                                                                                          defaults:self.defaults]];
}

/// Answers a parked operation. YES lets it go on to the quit check and the
/// swap; NO discards its staging.
- (void)resolveApproval:(BOOL)proceed forBundleID:(NSString *)bundleID {
    void (^reply)(BOOL) = self.pendingApprovals[bundleID];
    if (!reply) return;
    [self.pendingApprovals removeObjectForKey:bundleID];
    if (proceed) [self.inspectingBundleIDs removeObject:bundleID];   // it is the user's install now
    reply(proceed);
    [self rebuildRowModels];
    [self publishProgress];
}

/// The user asked to install a build that is parked at the approval step:
/// go straight on if nothing needs asking, otherwise ask.
- (void)continueParkedInstallForBundleID:(NSString *)bundleID {
    if ([self gateDecisionForBundleID:bundleID] == CDRNetworkGateDecisionNoAsk) {
        [self resolveApproval:YES forBundleID:bundleID];
        return;
    }
    [self presentNetworkApprovalForBundleID:bundleID];
}

- (void)presentNetworkApprovalForBundleID:(NSString *)bundleID {
    CDRAppRegistration *reg = [self registrationForBundleID:bundleID];
    CDRNetworkInspection *inspection = self.inspections[bundleID];
    if (!reg || !inspection || !self.pendingApprovals[bundleID]) return;

    NSMutableArray<CDRInterruptSheetDiffLine *> *diff = [NSMutableArray array];
    for (NSString *key in inspection.addedEntitlements) {
        [diff addObject:[CDRInterruptSheetDiffLine lineWithText:key added:YES]];
    }
    for (NSString *key in inspection.removedEntitlements) {
        [diff addObject:[CDRInterruptSheetDiffLine lineWithText:key added:NO]];
    }
    NSMutableArray<CDRInterruptSheetPolicyRow *> *policyRows = nil;
    // The policy is shown only when the gate's verdict is "ask, with policy".
    if ([self gateDecisionForBundleID:bundleID] == CDRNetworkGateDecisionAskWithPolicy) {
        policyRows = [NSMutableArray array];
        for (CDRInternetAccessPolicyRow *row in inspection.stagedPolicy.rows) {
            [policyRows addObject:[CDRInterruptSheetPolicyRow rowWithSubject:row.subject purpose:row.purpose]];
        }
    }

    __weak typeof(self) weakSelf = self;
    [self.presenter presentNetworkApprovalForAppNamed:reg.appURL.lastPathComponent.stringByDeletingPathExtension
                                             bundleID:bundleID
                                               appURL:reg.appURL
                                          fromVersion:inspection.installedVersion
                                            toVersion:inspection.stagedVersion
                                            diffLines:diff
                                           policyRows:policyRows
                                           completion:^(CDRInterruptSheetAction action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        switch (action) {
            case CDRInterruptSheetActionInstall:
                [CDRSharedLog log:[NSString stringWithFormat:@"%@: network access approved for %@.",
                                   bundleID, inspection.stagedVersion]];
                [self resolveApproval:YES forBundleID:bundleID];
                break;
            case CDRInterruptSheetActionSkipVersion: {
                // Remember the skip, discard the staged build, and decide
                // again so the row says "skipped".
                CDRManifest *manifest = self.lastManifests[bundleID];
                NSString *version = manifest.version ?: inspection.stagedVersion;
                [self.stateStore noteSkippedVersion:version forBundleID:bundleID at:[NSDate date]];
                [CDRSharedLog log:[NSString stringWithFormat:@"%@: skipping %@ at your request.", bundleID, version]];
                [self resolveApproval:NO forBundleID:bundleID];
                if (manifest) [self evaluateManifest:manifest registration:reg breakThrough:NO notify:NO];
                [self rebuildRowModels];
                break;
            }
            case CDRInterruptSheetActionDismiss:
                // The sheet couldn't be shown. The build stays parked and
                // the row keeps asking.
                break;
        }
    }];
}

/// The app is quitting: parked approvals are discarded, not carried over.
- (void)discardParkedApprovals {
    for (NSString *bundleID in self.pendingApprovals.allKeys) {
        [self resolveApproval:NO forBundleID:bundleID];
    }
}

#pragma mark - Row actions

- (void)performRowAction:(CDRAppRowActions)action forBundleID:(NSString *)bundleID {
    switch (action) {
        case CDRAppRowActionInstall: {
            // An update the user holds for manual install is confirmed once
            // more, with what it contains in front of them. That goes for a
            // major-version stop that also carries held categories.
            if (self.pendingApprovals[bundleID]) {
                // Already downloaded, verified and inspected: approve it (or
                // ask, if the gate says to) rather than start over.
                [self.inspectingBundleIDs removeObject:bundleID];
                [self continueParkedInstallForBundleID:bundleID];
                break;
            }
            CDRAppRegistration *reg = [self registrationForBundleID:bundleID];
            CDRManifest *manifest = self.knownManifests[bundleID];
            CDRUpdateDecision *decision = self.lastDecisions[bundleID];
            if (reg && manifest && decision.heldTypes != CDRReleaseNoteTypeSetNone && !self.operations[bundleID]) {
                CDRUpdatePreferences *preferences =
                    [CDRPolicyResolver effectivePreferencesForBundleID:bundleID defaults:self.defaults];
                NSArray<CDRRelease *> *releases = [manifest releasesNewerThanVersion:reg.installedShortVersion];
                __weak typeof(self) weakSelf = self;
                [self.presenter presentHeldUpdateForAppNamed:reg.appURL.lastPathComponent.stringByDeletingPathExtension
                                                    bundleID:bundleID
                                                      appURL:reg.appURL
                                                     version:manifest.version
                                                  heldGroups:CDRNoteGroupsOfTypes(releases, decision.heldTypes)
                                                   holdTypes:preferences.holdTypes
                                                  completion:^(BOOL install) {
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self || !install) return;   // Not now: the row stays Held
                    // The same consent path as any install.
                    [self.stateStore noteNotifiedVersion:manifest.version build:manifest.build
                                             forBundleID:bundleID at:[NSDate date]];
                    [self installApp:bundleID];
                }];
                break;
            }
            [self installApp:bundleID];
            break;
        }
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
        case CDRAppRowActionInstallDeferred: {
            // "Update now" on a deferred update: the click is the consent
            // (deferral.md break-through). It marks the version notified —
            // so retraction loudness applies from here on — and the update
            // is then decided like any surfaced one. If one of the user's
            // gates applies, the row moves to that gate instead of installing.
            CDRAppRegistration *reg = [self registrationForBundleID:bundleID];
            CDRManifest *manifest = self.lastManifests[bundleID];
            CDRUpdateDecision *last = self.lastDecisions[bundleID];
            if (!reg || !manifest || (last.outcome != CDRUpdateOutcomeDeferred
                                      && last.outcome != CDRUpdateOutcomeDeferredOffered)) break;
            [self.stateStore noteNotifiedVersion:manifest.version build:manifest.build
                                     forBundleID:bundleID at:[NSDate date]];
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@ taken out of deferral at your request.",
                               bundleID, manifest.version]];
            CDRUpdateDecision *now = [self evaluateManifest:manifest registration:reg breakThrough:NO notify:NO];
            if (now.outcome == CDRUpdateOutcomeAvailable) [self installApp:bundleID];
            [self rebuildRowModels];
            break;
        }
        case CDRAppRowActionAlwaysAllowMajor: {
            CDRAppPolicyOverride *override = CDRAppPolicyOverrideForBundleID(bundleID, self.defaults);
            override.stopAtMajorVersions = @NO;
            CDRSetAppPolicyOverride(override, bundleID, self.defaults);
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: major versions are now always allowed for this app.",
                               bundleID]];
            [self preferencesDidChange];
            break;
        }
        case CDRAppRowActionAcknowledge:
            // "Got it" on a retraction notice. The decision that raised it
            // already cleared the notified memory, so a fresh passive check
            // lands on plain "up to date" and replaces the notice.
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: retraction notice acknowledged.", bundleID]];
            CDRSetRetractionNotice(nil, bundleID, self.defaults);
            [self rebuildRowModels];
            [self checkApp:bundleID userInitiated:NO];
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
        // An inspect-ahead download is Conductor's own idea and has touched
        // nothing but staging: it never holds up quitting.
        if ([self.inspectingBundleIDs containsObject:bundleID]) continue;
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
        if (self.pendingApprovals[bundleID]) continue;   // parked for approval: nothing is happening
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

/// The operation has verified and inspected the staged build and is parked.
/// What happens next depends on who started it.
- (void)updateOperation:(CDRUpdateOperation *)op
             didInspect:(CDRNetworkInspection *)inspection
                  reply:(void (^)(BOOL proceed))reply {
    NSString *bundleID = op.registration.bundleID;
    if ([self.supersededBundleIDs containsObject:bundleID]) {
        // The update it was fetched for is no longer the one on offer.
        reply(NO);
        return;
    }
    self.inspections[bundleID] = inspection;
    for (NSString *warning in inspection.stagedPolicy.warnings) {
        [CDRSharedLog log:[NSString stringWithFormat:@"%@: Internet Access Policy — %@", bundleID, warning]];
    }
    CDRNetworkGateDecision gate = [self gateDecisionForBundleID:bundleID];

    if ([self.inspectingBundleIDs containsObject:bundleID]) {
        // Conductor looked ahead on its own. It stops here until the user
        // clicks — whatever the gate says. If the gate says to ask, the row
        // moves to NEEDS YOU and a passive notice says why.
        self.pendingApprovals[bundleID] = [reply copy];
        if (gate != CDRNetworkGateDecisionNoAsk) {
            NSString *appName = op.registration.appURL.lastPathComponent.stringByDeletingPathExtension;
            NSString *reason = gate == CDRNetworkGateDecisionAskWithPolicy
                ? [NSString stringWithFormat:@"%@ adds internet access and says why. Approve it in Conductor.",
                   inspection.stagedVersion]
                : [NSString stringWithFormat:@"%@ adds internet access and doesn’t say why. Review it in Conductor.",
                   inspection.stagedVersion];
            [self.presenter notifyUpdateNeedsAttentionForAppNamed:appName bundleID:bundleID
                                                          version:inspection.stagedVersion reason:reason];
        }
        [self rebuildRowModels];
        [self publishProgress];
        return;
    }

    // The user started this install.
    if (gate == CDRNetworkGateDecisionNoAsk) {
        reply(YES);
        return;
    }
    self.pendingApprovals[bundleID] = [reply copy];
    [self rebuildRowModels];
    [self publishProgress];
    [self presentNetworkApprovalForBundleID:bundleID];
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
    // Whether Conductor started this on its own, to inspect — in which case
    // the user never asked for an install and must not be told one failed.
    BOOL inspectAhead = [self.inspectingBundleIDs containsObject:bundleID];
    [self.inspectingBundleIDs removeObject:bundleID];
    [self.supersededBundleIDs removeObject:bundleID];
    [self.pendingApprovals removeObjectForKey:bundleID];
    [self.inspections removeObjectForKey:bundleID];
    [self publishProgress];

    if (error && [error.domain isEqualToString:CDRErrorDomain] && error.code == CDRErrorApprovalDeclined) {
        // Declined, skipped, superseded or discarded at quit: informational.
        // Staging is gone; the installed app was never touched.
        [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
        [self rebuildRowModels];
        return;
    }

    if (error) {
        if ([error.domain isEqualToString:CDRErrorDomain] && error.code == CDRErrorUpdateCancelled) {
            // User-requested cancellation of a parked update: informational.
            // The known manifest survives so Install works without re-checking.
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
            [self rebuildRowModels];
            return;
        }
        BOOL retraction = [error.userInfo[CDRErrorIsRetractionKey] boolValue]
            || ![self.reachedDownloadBundleIDs containsObject:bundleID];
        if ([error.domain isEqualToString:CDRErrorDomain] && error.code == CDRErrorDowngradeRefused && retraction) {
            // The operation's last-moment manifest re-check caught a
            // retraction between notify and install (retraction.md) — this is
            // State A, not a generic failure. The operation stays state-free;
            // the state reaction lives here.
            NSString *retractedVersion = self.knownManifests[bundleID].version
                ?: [self.stateStore stateForBundleID:bundleID].lastNotifiedVersion;
            NSDate *advertisedAt = [self.stateStore stateForBundleID:bundleID].notifiedAt;
            [self.stateStore clearNotifiedVersionForBundleID:bundleID at:[NSDate date]];
            [self.knownManifests removeObjectForKey:bundleID];
            [self.lastDecisions removeObjectForKey:bundleID];
            [self.lastManifests removeObjectForKey:bundleID];
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
            if (retractedVersion) {
                // Same notice a check would leave, so the row keeps its
                // banner if the sheet can't be shown or isn't read.
                CDRSetRetractionNotice([CDRRetractionNotice noticeWithVersion:retractedVersion
                                                                  advertisedAt:advertisedAt
                                                                      pulledAt:[NSDate date]],
                                       bundleID, self.defaults);
            }
            if (inspectAhead) {
                // Found while Conductor was looking ahead on its own: the
                // same passive notice a scheduled check would post.
                [self.presenter notifyRetractedPending:error.localizedDescription bundleID:bundleID
                                             vendorURL:(error.userInfo[CDRErrorVendorURLKey]
                                                        ?: op.registration.vendorURL)];
                [self rebuildRowModels];
                return;
            }
            // The user pressed Install: a user-started flow.
            __weak typeof(self) weakSelf = self;
            [self.presenter presentRetractionForAppNamed:appName
                                                bundleID:bundleID
                                                  appURL:op.registration.appURL
                                        retractedVersion:retractedVersion ?: @"the update"
                                        installedVersion:op.registration.installedShortVersion
                                                 message:error.localizedDescription
                                               vendorURL:(error.userInfo[CDRErrorVendorURLKey]
                                                          ?: op.registration.vendorURL)
                                              completion:^(BOOL acknowledged) {
                if (acknowledged) [weakSelf performRowAction:CDRAppRowActionAcknowledge forBundleID:bundleID];
            }];
            [self rebuildRowModels];
            return;
        }
        if (inspectAhead) {
            // Couldn't look ahead. Say so in the log and leave the update
            // offered as it was; an install the user starts will report its
            // own failure. Not retried for this version.
            [CDRSharedLog log:[NSString stringWithFormat:@"%@: couldn’t inspect %@ ahead of time — %@",
                               bundleID, op.manifestVersion, error.localizedDescription]];
            self.failedInspectionVersions[bundleID] = op.manifestVersion;
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

/// The signing organization shown beside the app's name. Read from the
/// installed bundle's certificate once per path; display only.
- (nullable NSString *)developerNameForRegistration:(CDRAppRegistration *)reg {
    NSString *key = reg.appURL.path;
    if (!key) return nil;
    id cached = self.developerNames[key];
    if (!cached) {
        cached = [CDRBundleInspector developerNameForBundleAtURL:reg.appURL] ?: [NSNull null];
        self.developerNames[key] = cached;
    }
    return cached == [NSNull null] ? nil : cached;
}

- (void)rebuildRowModels {
    NSSet<NSString *> *ignored = CDRIgnoredBundleIDs(self.defaults);
    NSMutableArray<CDRAppRowModel *> *rows = [NSMutableArray arrayWithCapacity:self.registrations.count];
    for (CDRAppRegistration *reg in self.registrations) {
        NSString *bundleID = reg.bundleID;
        CDRUpdatePhase phase = self.operationPhases[bundleID]
            ? self.operationPhases[bundleID].integerValue : CDRUpdatePhaseIdle;
        CDRAppRowContext *context = [[CDRAppRowContext alloc] init];
        context.developerName = [self developerNameForRegistration:reg];
        context.preferences = [CDRPolicyResolver effectivePreferencesForBundleID:bundleID defaults:self.defaults];
        context.pendingRetraction = CDRRetractionNoticeForBundleID(bundleID, self.defaults);

        CDRInstalledNetworkInfo *network = [self installedNetworkInfoForRegistration:reg];
        context.installedNetworkKnown = YES;
        context.installedPosture = network.posture;
        context.installedPolicy = network.policy;
        context.installedEntitlementKeys = network.entitlementKeys;
        context.teamID = network.teamID;
        context.inspection = self.inspections[bundleID];
        context.inspecting = [self.inspectingBundleIDs containsObject:bundleID]
            && self.operations[bundleID] != nil && self.pendingApprovals[bundleID] == nil;
        context.approvalParked = self.pendingApprovals[bundleID] != nil;
        context.networkApprovalNeeded = context.approvalParked
            && [self gateDecisionForBundleID:bundleID] != CDRNetworkGateDecisionNoAsk;
        [rows addObject:[CDRAppRowModel modelForRegistration:reg
                                                lastDecision:self.lastDecisions[bundleID]
                                             decidedManifest:self.lastManifests[bundleID]
                                                   lastError:self.lastErrors[bundleID]
                                                     ignored:[ignored containsObject:bundleID]
                                              operationPhase:phase
                                                      parked:[self.parkedBundleIDs containsObject:bundleID]
                                                     context:context]];
    }
    self.rowModels = rows;
    if (self.onRowModelsChanged) self.onRowModelsChanged();
}

@end
