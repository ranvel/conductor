//
//  CDRAppRowModel.m
//  Conductor
//

#import "CDRAppRowModel.h"
#import "CDRAppRegistration.h"
#import "CDRUpdatePolicy.h"
#import "CDRManifest.h"
#import "CDRErrors.h"

@interface CDRAppRowModel ()
@property (nonatomic, readwrite) NSString *bundleID;
@property (nonatomic, readwrite) NSString *appName;
@property (nonatomic, readwrite) NSString *installedVersionDisplay;
@property (nonatomic, readwrite) CDRAppRowState state;
@property (nonatomic, readwrite) NSString *stateLine;
@property (nonatomic, readwrite) CDRAppRowActions actions;
@property (nonatomic, readwrite) BOOL contributesToBadge;
@property (nonatomic, readwrite, nullable) NSURL *vendorURL;
@property (nonatomic, readwrite, nullable) NSString *availableVersion;
@end

@implementation CDRAppRowModel

static NSString *MediumDate(NSDate *date) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterMediumStyle;
    fmt.timeStyle = NSDateFormatterNoStyle;
    return [fmt stringFromDate:date];
}

+ (instancetype)modelForRegistration:(CDRAppRegistration *)registration
                        lastDecision:(CDRUpdateDecision *)decision
                     decidedManifest:(CDRManifest *)manifest
                           lastError:(NSError *)error
                             ignored:(BOOL)ignored
                      operationPhase:(CDRUpdatePhase)operationPhase
                              parked:(BOOL)parked {
    CDRAppRowModel *model = [[CDRAppRowModel alloc] init];
    model.bundleID = registration.bundleID;
    model.appName = registration.appURL.lastPathComponent.stringByDeletingPathExtension;
    model.installedVersionDisplay = registration.installedBuildVersion
        ? [NSString stringWithFormat:@"%@ (%@)", registration.installedShortVersion, registration.installedBuildVersion]
        : registration.installedShortVersion;
    model.vendorURL = registration.vendorURL;

    CDRAppRowActions ignoreToggle = ignored ? CDRAppRowActionUnignore : CDRAppRowActionIgnore;

    if (parked) {
        model.state = CDRAppRowStateWaitingForQuit;
        model.stateLine = [NSString stringWithFormat:@"waiting for %@ to quit", model.appName];
        model.actions = CDRAppRowActionCancelPending;
        return model;
    }

    BOOL working = (operationPhase != CDRUpdatePhaseIdle &&
                    operationPhase != CDRUpdatePhaseDone &&
                    operationPhase != CDRUpdatePhaseFailed);
    if (working) {
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
        NSURL *vendor = error.userInfo[CDRErrorVendorURLKey] ?: registration.vendorURL;
        model.vendorURL = vendor;
        model.actions = CDRAppRowActionCheckNow | ignoreToggle | (vendor ? CDRAppRowActionVendorSite : 0);
        return model;
    }

    if (!decision) {
        model.state = CDRAppRowStateUnknown;
        model.stateLine = @"not yet checked";
        model.actions = CDRAppRowActionCheckNow | ignoreToggle;
        return model;
    }

    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable: {
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
            model.state = CDRAppRowStateDeferred;
            model.stateLine = [NSString stringWithFormat:@"%@ deferred until %@",
                               manifest.version, MediumDate(decision.deferredUntil)];
            model.actions = CDRAppRowActionCheckNow | ignoreToggle;
            break;
        }

        case CDRUpdateOutcomeRetractedPending: {
            // State A: the loudness is the notification at decision time; the
            // row afterward is calm — nothing is installable.
            model.state = CDRAppRowStateUpToDate;
            model.stateLine = [NSString stringWithFormat:@"update %@ retracted — you have the latest version",
                               decision.retractedVersion];
            model.actions = CDRAppRowActionCheckNow | ignoreToggle
                | (registration.vendorURL ? CDRAppRowActionVendorSite : 0);
            model.contributesToBadge = YES;
            break;
        }

        case CDRUpdateOutcomeRetractedInstalled: {
            model.state = CDRAppRowStateRecalled;
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

@end
