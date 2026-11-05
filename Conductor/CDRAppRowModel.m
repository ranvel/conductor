//
//  CDRAppRowModel.m
//  Conductor
//

#import "CDRAppRowModel.h"
#import "CDRAppRowModel_Private.h"
#import "CDRAppRegistration.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdatePreferences.h"
#import "CDRRetractionNotices.h"
#import "CDRManifest.h"
#import "CDRVersion.h"
#import "CDRErrors.h"

const NSInteger CDRAppRowSectionCount = CDRAppRowSectionNotChecked + 1;

CDRAppRowSection CDRAppRowSectionForState(CDRAppRowState state) {
    switch (state) {
        case CDRAppRowStateNeedsNetworkApproval:
        case CDRAppRowStateHeld:
        case CDRAppRowStateStoppedAtMajor:
        case CDRAppRowStateRetracted:
        case CDRAppRowStateRecalled:
            return CDRAppRowSectionNeedsYou;

        case CDRAppRowStateAvailable:
        case CDRAppRowStateDeferred:
        case CDRAppRowStateInspecting:
        case CDRAppRowStateWorking:
        case CDRAppRowStateWaitingForQuit:
            return CDRAppRowSectionUpdates;

        case CDRAppRowStateUpToDate:
            return CDRAppRowSectionUpToDate;

        case CDRAppRowStateUnknown:
        case CDRAppRowStateCheckFailed:
        case CDRAppRowStateIgnored:
            return CDRAppRowSectionNotChecked;
    }
    return CDRAppRowSectionNotChecked;
}

NSString *CDRAppRowSectionTitle(CDRAppRowSection section) {
    switch (section) {
        case CDRAppRowSectionNeedsYou: return @"NEEDS YOU";
        case CDRAppRowSectionUpdates: return @"UPDATES";
        case CDRAppRowSectionUpToDate: return @"UP TO DATE";
        case CDRAppRowSectionNotChecked: return @"NOT CHECKED";
    }
    return @"";
}

@implementation CDRAppRowContext
@end

@implementation CDRAppRowModel

static NSString *MediumDate(NSDate *date) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterMediumStyle;
    fmt.timeStyle = NSDateFormatterNoStyle;
    return [fmt stringFromDate:date];
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _releases = @[];
    _shownTypes = CDRReleaseNoteTypeSetAll;
    return self;
}

+ (instancetype)modelForRegistration:(CDRAppRegistration *)registration
                        lastDecision:(CDRUpdateDecision *)decision
                     decidedManifest:(CDRManifest *)manifest
                           lastError:(NSError *)error
                             ignored:(BOOL)ignored
                      operationPhase:(CDRUpdatePhase)operationPhase
                              parked:(BOOL)parked {
    return [self modelForRegistration:registration lastDecision:decision decidedManifest:manifest
                            lastError:error ignored:ignored operationPhase:operationPhase
                               parked:parked context:nil];
}

+ (instancetype)modelForRegistration:(CDRAppRegistration *)registration
                        lastDecision:(CDRUpdateDecision *)decision
                     decidedManifest:(CDRManifest *)manifest
                           lastError:(NSError *)error
                             ignored:(BOOL)ignored
                      operationPhase:(CDRUpdatePhase)operationPhase
                              parked:(BOOL)parked
                             context:(CDRAppRowContext *)context {
    CDRAppRowModel *model = [[CDRAppRowModel alloc] init];
    model.bundleID = registration.bundleID;
    model.appURL = registration.appURL;
    model.appName = registration.appURL.lastPathComponent.stringByDeletingPathExtension;
    model.installedVersion = registration.installedShortVersion;
    model.installedVersionDisplay = registration.installedBuildVersion
        ? [NSString stringWithFormat:@"%@ (%@)", registration.installedShortVersion, registration.installedBuildVersion]
        : registration.installedShortVersion;
    model.vendorURL = registration.vendorURL;
    model.operationPhase = operationPhase;
    model.developerName = context.developerName;
    if (context.preferences) {
        model.shownTypes = context.preferences.shownTypes;
        model.exposesDeveloperDetail = context.preferences.exposesDeveloperDetail;
        if (context.preferences.soakDuration != CDRSoakDurationOff) {
            model.deferralDurationName =
                CDRSoakDurationDisplayName(context.preferences.soakDuration).lowercaseString;
        }
    }

    CDRAppRowActions ignoreToggle = ignored ? CDRAppRowActionUnignore : CDRAppRowActionIgnore;

    if (parked) {
        [model adoptUpdateFromManifest:manifest installedVersion:registration.installedShortVersion];
        model.state = CDRAppRowStateWaitingForQuit;
        model.stateLine = [NSString stringWithFormat:@"waiting for %@ to quit", model.appName];
        model.actions = CDRAppRowActionCancelPending;
        return model;
    }

    BOOL working = (operationPhase != CDRUpdatePhaseIdle &&
                    operationPhase != CDRUpdatePhaseDone &&
                    operationPhase != CDRUpdatePhaseFailed);
    if (working) {
        [model adoptUpdateFromManifest:manifest installedVersion:registration.installedShortVersion];
        model.state = CDRAppRowStateWorking;
        model.stateLine = [NSString stringWithFormat:@"%@ …", CDRUpdatePhaseName(operationPhase)];
        model.actions = CDRAppRowActionNone;
        return model;
    }

    if (ignored) {
        model.state = CDRAppRowStateIgnored;
        model.stateLine = @"ignored";
        model.actions = CDRAppRowActionCheckNow | CDRAppRowActionUnignore;
        return model;
    }

    if (error) {
        model.state = CDRAppRowStateCheckFailed;
        model.stateLine = [NSString stringWithFormat:@"check failed — %@", error.localizedDescription];
        model.errorDescription = error.localizedDescription;
        NSURL *vendor = error.userInfo[CDRErrorVendorURLKey] ?: registration.vendorURL;
        model.vendorURL = vendor;
        model.actions = CDRAppRowActionCheckNow | ignoreToggle | (vendor ? CDRAppRowActionVendorSite : 0);
        return model;
    }

    // An unacknowledged retraction outlives the decision that found it: with
    // no decision yet this launch, or one that says "up to date", the row
    // still carries the notice until the user says "Got it".
    CDRRetractionNotice *notice = context.pendingRetraction;
    BOOL quietOutcome = !decision
        || decision.outcome == CDRUpdateOutcomeUpToDate
        || decision.outcome == CDRUpdateOutcomeDroppedSilently;
    if (notice && quietOutcome) {
        [model becomeRetractedVersion:notice.version registration:registration
                          changelogURL:manifest.changelogURL ignoreToggle:ignoreToggle];
        model.retractionAdvertisedDate = notice.advertisedAt;
        model.retractionPulledDate = notice.pulledAt;
        return model;
    }

    if (!decision) {
        model.state = CDRAppRowStateUnknown;
        model.stateLine = @"not yet checked";
        model.actions = CDRAppRowActionCheckNow | ignoreToggle;
        return model;
    }

    model.urgency = decision.urgency;

    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable: {
            [model adoptUpdateFromManifest:manifest installedVersion:registration.installedShortVersion];
            model.state = CDRAppRowStateAvailable;
            model.availableVersion = manifest.version;
            NSString *line = [NSString stringWithFormat:@"%@ available (installed: %@)",
                              manifest.version, registration.installedShortVersion];
            if (decision.urgency != CDRUrgencyNone) {
                line = [line stringByAppendingString:@" — flagged urgent by the developer"];
            }
            model.stateLine = line;
            model.actions = CDRAppRowActionInstall | CDRAppRowActionCheckNow | ignoreToggle;
            model.contributesToBadge = YES;
            break;
        }

        case CDRUpdateOutcomeDeferred:
        case CDRUpdateOutcomeDeferredOffered: {
            [model adoptUpdateFromManifest:manifest installedVersion:registration.installedShortVersion];
            model.state = CDRAppRowStateDeferred;
            model.deferredUntil = decision.deferredUntil;
            model.stateLine = [NSString stringWithFormat:@"%@ deferred until %@",
                               manifest.version, MediumDate(decision.deferredUntil)];
            model.actions = CDRAppRowActionCheckNow | CDRAppRowActionInstallDeferred | ignoreToggle;
            break;
        }

        case CDRUpdateOutcomeHeld: {
            // Surfaced, installable — but only on a deliberate click.
            [model adoptUpdateFromManifest:manifest installedVersion:registration.installedShortVersion];
            model.state = CDRAppRowStateHeld;
            model.heldTypes = decision.heldTypes;
            model.availableVersion = manifest.version;
            model.stateLine = [NSString stringWithFormat:@"%@ held for manual install — %@",
                               manifest.version,
                               CDRUpdateGateReasonCopy(decision, registration.installedShortVersion,
                                                       manifest.version)];
            model.actions = CDRAppRowActionInstall | CDRAppRowActionCheckNow | ignoreToggle;
            model.contributesToBadge = YES;
            break;
        }

        case CDRUpdateOutcomeStoppedAtMajor: {
            [model adoptUpdateFromManifest:manifest installedVersion:registration.installedShortVersion];
            model.state = CDRAppRowStateStoppedAtMajor;
            // A hold may apply as well; the major stop takes the state line.
            model.heldTypes = decision.heldTypes;
            model.availableVersion = manifest.version;
            model.stateLine = [NSString stringWithFormat:@"%@ stopped at major version (installed: %@)",
                               manifest.version, registration.installedShortVersion];
            model.actions = CDRAppRowActionInstall | CDRAppRowActionAlwaysAllowMajor
                | CDRAppRowActionCheckNow | ignoreToggle;
            model.contributesToBadge = YES;
            break;
        }

        case CDRUpdateOutcomeRetractedPending: {
            // State A: nothing is installable. The row asks only to be read.
            [model becomeRetractedVersion:decision.retractedVersion registration:registration
                              changelogURL:manifest.changelogURL ignoreToggle:ignoreToggle];
            if (notice && [notice.version isEqualToString:decision.retractedVersion]) {
                model.retractionAdvertisedDate = notice.advertisedAt;
                model.retractionPulledDate = notice.pulledAt;
            }
            break;
        }

        case CDRUpdateOutcomeRetractedInstalled: {
            model.state = CDRAppRowStateRecalled;
            model.retractedVersion = decision.retractedVersion;
            model.noteTypes = CDRReleaseNoteTypeSetRetracted;
            model.changelogURL = manifest.changelogURL;
            model.stateLine = @"recalled — see developer's site";
            model.actions = CDRAppRowActionCheckNow | ignoreToggle
                | (registration.vendorURL ? CDRAppRowActionVendorSite : 0);
            break;
        }

        case CDRUpdateOutcomeUpToDate:
        case CDRUpdateOutcomeDroppedSilently: {
            model.state = CDRAppRowStateUpToDate;
            model.stateLine = [NSString stringWithFormat:@"up to date (%@)", registration.installedShortVersion];
            model.actions = CDRAppRowActionCheckNow | ignoreToggle;
            break;
        }
    }
    return model;
}

- (void)becomeRetractedVersion:(NSString *)version
                  registration:(CDRAppRegistration *)registration
                  changelogURL:(nullable NSURL *)changelogURL
                  ignoreToggle:(CDRAppRowActions)ignoreToggle {
    self.state = CDRAppRowStateRetracted;
    self.retractedVersion = version;
    self.noteTypes = CDRReleaseNoteTypeSetRetracted;
    self.changelogURL = changelogURL;
    self.stateLine = [NSString stringWithFormat:@"update %@ retracted — you have the latest version", version];
    self.actions = CDRAppRowActionCheckNow | CDRAppRowActionAcknowledge | ignoreToggle
        | (registration.vendorURL ? CDRAppRowActionVendorSite : 0);
    self.contributesToBadge = YES;
}

/// Fills everything the window shows about a pending update — the version
/// pair, the notes, the dots. Only when the manifest really is newer than
/// what is installed: display data never invents an update.
- (void)adoptUpdateFromManifest:(CDRManifest *)manifest installedVersion:(NSString *)installedVersion {
    if (!manifest) return;
    NSArray<CDRRelease *> *releases = [manifest releasesNewerThanVersion:installedVersion];
    if (releases.count == 0) return;
    self.advertisedVersion = manifest.version;
    self.releases = releases;
    self.noteTypes = releases.firstObject.typeSet;
    self.releaseDate = releases.firstObject.date;
    self.artifactSize = manifest.artifactSize;
    self.changelogURL = manifest.changelogURL;
}

#pragma mark - Derived

- (CDRAppRowSection)section {
    return CDRAppRowSectionForState(self.state);
}

- (NSString *)versionPairDisplay {
    if (self.advertisedVersion) {
        return [NSString stringWithFormat:@"%@ → %@", self.installedVersion, self.advertisedVersion];
    }
    return self.installedVersion ?: @"";
}

- (NSArray<NSString *> *)includedVersions {
    if (self.releases.count < 2) return @[];
    NSMutableArray<NSString *> *versions = [NSMutableArray array];
    for (NSUInteger i = 1; i < self.releases.count; i++) [versions addObject:self.releases[i].version];
    return versions;
}

- (NSString *)stateSymbolName {
    switch (self.state) {
        case CDRAppRowStateNeedsNetworkApproval: return @"exclamationmark.triangle";
        case CDRAppRowStateHeld: return @"pause.circle";
        case CDRAppRowStateRetracted:
        case CDRAppRowStateRecalled: return @"arrow.uturn.backward";
        case CDRAppRowStateAvailable: return @"arrow.down.to.line";
        case CDRAppRowStateInspecting: return @"magnifyingglass";
        case CDRAppRowStateDeferred: return @"clock";
        case CDRAppRowStateStoppedAtMajor: return @"arrow.up.to.line";
        case CDRAppRowStateUpToDate: return @"checkmark";
        case CDRAppRowStateWorking: return @"arrow.triangle.2.circlepath";
        case CDRAppRowStateWaitingForQuit: return @"hourglass";
        case CDRAppRowStateCheckFailed: return @"exclamationmark.circle";
        case CDRAppRowStateUnknown: return @"circle.dashed";
        case CDRAppRowStateIgnored: return @"eye.slash";
    }
    return @"circle";
}

- (CDRAppRowTone)stateTone {
    switch (self.state) {
        case CDRAppRowStateNeedsNetworkApproval:
        case CDRAppRowStateHeld:
        case CDRAppRowStateRetracted:
        case CDRAppRowStateRecalled:
            return CDRAppRowToneAttention;
        case CDRAppRowStateAvailable:
            return CDRAppRowTonePrimary;
        default:
            return CDRAppRowToneSecondary;
    }
}

- (NSString *)shortStateLineAsOf:(NSDate *)now {
    switch (self.state) {
        case CDRAppRowStateNeedsNetworkApproval:
            return @"Approve network access";
        case CDRAppRowStateHeld: {
            for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
                if (CDRReleaseNoteTypeSetContains(self.heldTypes, (CDRReleaseNoteType)i)) {
                    return [NSString stringWithFormat:@"Held · includes %@",
                            CDRReleaseNoteTypeNounPhrase((CDRReleaseNoteType)i)];
                }
            }
            return @"Held for manual install";
        }
        case CDRAppRowStateRetracted:
            return [NSString stringWithFormat:@"%@ was retracted", self.retractedVersion ?: @"An update"];
        case CDRAppRowStateRecalled:
            return [NSString stringWithFormat:@"%@ was recalled", self.retractedVersion ?: @"This build"];
        case CDRAppRowStateAvailable:
            return @"Update available";
        case CDRAppRowStateInspecting:
            return @"Inspecting…";
        case CDRAppRowStateDeferred: {
            NSTimeInterval left = [self.deferredUntil timeIntervalSinceDate:now];
            if (!self.deferredUntil || left <= 0) return @"Deferred";
            if (left < 86400.0) return @"Deferred · less than a day left";
            NSInteger days = (NSInteger)ceil(left / 86400.0);
            if (days == 1) return @"Deferred · 1 day left";
            return [NSString stringWithFormat:@"Deferred · %ld days left", (long)days];
        }
        case CDRAppRowStateStoppedAtMajor:
            return @"Stopped at major version";
        case CDRAppRowStateUpToDate:
            return @"Up to date";
        case CDRAppRowStateWorking:
            switch (self.operationPhase) {
                case CDRUpdatePhaseFetching: return @"Checking…";
                case CDRUpdatePhaseDownloading: return @"Downloading…";
                case CDRUpdatePhaseExtracting: return @"Unpacking…";
                case CDRUpdatePhaseVerifying: return @"Verifying…";
                case CDRUpdatePhaseAwaitingQuit: return @"Waiting for the app to quit…";
                default: return @"Installing…";
            }
        case CDRAppRowStateWaitingForQuit:
            return @"Installs when you quit it";
        case CDRAppRowStateCheckFailed:
            return @"Couldn't check";
        case CDRAppRowStateUnknown:
            return @"Not checked yet";
        case CDRAppRowStateIgnored:
            return @"Ignored";
    }
    return @"";
}

@end
