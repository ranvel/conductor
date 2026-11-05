//
//  CDRUpdatePolicy.m
//  Conductor
//

#import "CDRUpdatePolicy.h"
#import "CDRUpdatePreferences.h"
#import "CDRAppRegistration.h"
#import "CDRAppUpdateState.h"
#import "CDRVersion.h"

NSString * const CDRSoakDurationDefaultsKey = @"CDRSoakDuration";

NSTimeInterval CDRSoakDurationInterval(CDRSoakDuration duration) {
    switch (duration) {
        case CDRSoakDurationOff: return 0;
        case CDRSoakDurationOneDay: return 24.0 * 60.0 * 60.0;
        case CDRSoakDurationOneWeek: return 7.0 * 24.0 * 60.0 * 60.0;
        case CDRSoakDurationThreeDays: return 3.0 * 24.0 * 60.0 * 60.0;
    }
    return 0;
}

NSArray<NSNumber *> *CDRSoakDurationChoices(void) {
    return @[@(CDRSoakDurationOff), @(CDRSoakDurationOneDay),
             @(CDRSoakDurationThreeDays), @(CDRSoakDurationOneWeek)];
}

NSString *CDRSoakDurationDisplayName(CDRSoakDuration duration) {
    switch (duration) {
        case CDRSoakDurationOff: return @"Off";
        case CDRSoakDurationOneDay: return @"1 day";
        case CDRSoakDurationThreeDays: return @"3 days";
        case CDRSoakDurationOneWeek: return @"1 week";
    }
    return @"Off";
}

CDRSoakDuration CDRSoakDurationFromDefaultsToken(NSString *token) {
    if ([token isKindOfClass:[NSString class]]) {
        if ([token isEqualToString:@"1d"]) return CDRSoakDurationOneDay;
        if ([token isEqualToString:@"3d"]) return CDRSoakDurationThreeDays;
        if ([token isEqualToString:@"1w"]) return CDRSoakDurationOneWeek;
    }
    return CDRSoakDurationOff;
}

NSString *CDRSoakDurationDefaultsToken(CDRSoakDuration duration) {
    switch (duration) {
        case CDRSoakDurationOff: return @"off";
        case CDRSoakDurationOneDay: return @"1d";
        case CDRSoakDurationOneWeek: return @"1w";
        case CDRSoakDurationThreeDays: return @"3d";
    }
    return @"off";
}

#pragma mark - Decision

@interface CDRUpdateDecision ()
- (instancetype)initWithOutcome:(CDRUpdateOutcome)outcome
                  deferredUntil:(NSDate *)deferredUntil
               retractedVersion:(NSString *)retractedVersion
                        urgency:(CDRUrgency)urgency
                      heldTypes:(CDRReleaseNoteTypeSet)heldTypes
                stateAfterCheck:(CDRAppUpdateState *)stateAfterCheck;
@end

@implementation CDRUpdateDecision

- (instancetype)initWithOutcome:(CDRUpdateOutcome)outcome
                  deferredUntil:(NSDate *)deferredUntil
               retractedVersion:(NSString *)retractedVersion
                        urgency:(CDRUrgency)urgency
                      heldTypes:(CDRReleaseNoteTypeSet)heldTypes
                stateAfterCheck:(CDRAppUpdateState *)stateAfterCheck {
    self = [super init];
    if (self) {
        _outcome = outcome;
        _heldTypes = heldTypes;
        _stoppedAtMajor = (outcome == CDRUpdateOutcomeStoppedAtMajor);
        _deferredUntil = deferredUntil;
        _retractedVersion = retractedVersion;
        _urgency = urgency;
        _stateAfterCheck = stateAfterCheck;
    }
    return self;
}

@end

@implementation CDRUpdatePolicy

+ (CDRUpdateDecision *)decisionForRegistration:(CDRAppRegistration *)registration
                                      manifest:(CDRManifest *)manifest
                                         state:(CDRAppUpdateState *)state
                                   preferences:(CDRUpdatePreferences *)preferences
                                  breakThrough:(BOOL)breakThrough
                                           now:(NSDate *)now {
    CDRSoakDuration soakDuration = preferences.soakDuration;
    NSString *latest = manifest.version;
    NSString *installed = registration.installedShortVersion;
    CDRAppUpdateState *prior = state
        ?: [CDRAppUpdateState emptyStateWithBundleID:registration.bundleID at:now];

    // Ingest unconditionally (deferral.md: "ingested immediately but hidden"):
    // last_seen moves to the advertised latest, first_seen is set-once, and a
    // superseded never-notified soak (vX+1 under a fresh vX+2) is pruned away.
    CDRAppUpdateState *ingested = [prior stateBySeeingVersion:latest build:manifest.build at:now];

    CDRUpdateDecision *(^decision)(CDRUpdateOutcome, NSDate *, NSString *, CDRAppUpdateState *) =
        ^(CDRUpdateOutcome outcome, NSDate *deferredUntil, NSString *retracted, CDRAppUpdateState *after) {
            return [[CDRUpdateDecision alloc] initWithOutcome:outcome
                                                deferredUntil:deferredUntil
                                             retractedVersion:retracted
                                                      urgency:manifest.urgency
                                                    heldTypes:CDRReleaseNoteTypeSetNone
                                              stateAfterCheck:after];
        };

    // The user's two gates, applied only to an update that is being surfaced
    // (every path below that used to end in plain Available). Notes are
    // display data and the manifest is unauthenticated, so a gate can only
    // ever ask for one more deliberate click — it is never a security input,
    // and nothing here reaches verification.
    CDRUpdateDecision *(^surfaced)(CDRAppUpdateState *) = ^(CDRAppUpdateState *after) {
        CDRReleaseNoteTypeSet present = CDRReleaseNoteTypeSetNone;
        for (CDRRelease *release in [manifest releasesNewerThanVersion:installed]) {
            present |= release.typeSet;   // the advertised release and every skipped one
        }
        CDRReleaseNoteTypeSet held = present & preferences.holdTypes;
        BOOL major = preferences.stopAtMajorVersions
            && [CDRVersion isMajorUpgradeFrom:installed to:latest];
        CDRUpdateOutcome outcome = major ? CDRUpdateOutcomeStoppedAtMajor
            : (held != CDRReleaseNoteTypeSetNone ? CDRUpdateOutcomeHeld : CDRUpdateOutcomeAvailable);
        return [[CDRUpdateDecision alloc] initWithOutcome:outcome
                                            deferredUntil:nil
                                         retractedVersion:nil
                                                  urgency:manifest.urgency
                                                heldTypes:held
                                          stateAfterCheck:after];
    };

    // Retraction is only observable as a transition against what was surfaced
    // (retraction.md: "detection requires memory") — never inferred from
    // installed > latest alone, which a manually installed beta would trip.
    NSString *notified = prior.lastNotifiedVersion;
    if (notified && [CDRVersion compare:latest to:notified] == NSOrderedAscending) {
        if ([CDRVersion compare:installed to:latest] == NSOrderedDescending) {
            // State B: the recalled build is installed. Notified state is
            // retained so this keeps firing until the manifest advertises
            // ≥ installed again — the gate then goes quiet by construction.
            return decision(CDRUpdateOutcomeRetractedInstalled, nil, notified, ingested);
        }
        // State A: promise broken, nothing bad installed. Clearing the
        // notified fields makes the loudness one-time-ever.
        return decision(CDRUpdateOutcomeRetractedPending, nil, notified,
                        [ingested stateByClearingNotifiedAt:now]);
    }

    BOOL newer = [CDRVersion isVersion:latest build:manifest.build
                             newerThan:installed build:registration.installedBuildVersion];
    if (!newer) {
        // A never-surfaced version that vanished is dropped silently — no
        // promise was made, so no correction is owed (retraction.md).
        NSString *prevSeen = prior.lastSeenVersion;
        BOOL droppedSoak = prevSeen != nil
            && (!notified || [CDRVersion compare:prevSeen to:notified] != NSOrderedSame)
            && [CDRVersion isVersion:prevSeen build:prior.lastSeenBuild
                           newerThan:installed build:registration.installedBuildVersion]
            && [CDRVersion compare:latest to:prevSeen] == NSOrderedAscending;
        return decision(droppedSoak ? CDRUpdateOutcomeDroppedSilently : CDRUpdateOutcomeUpToDate,
                        nil, nil, ingested);
    }

    CDRAppUpdateState *notifiedState = [ingested stateByNotingNotifiedVersion:latest
                                                                        build:manifest.build
                                                                           at:now];

    // Urgency bypasses the soak window only — verification, the last-moment
    // re-check, and user consent are all unconditional (deferral.md). Marking
    // notified means retraction loudness now applies to this version.
    if (manifest.urgency != CDRUrgencyNone) {
        return surfaced(notifiedState);
    }

    // Already surfaced: re-show without re-gating on soak (and without
    // refreshing notified_at — the promise was already made).
    if (notified && [CDRVersion compare:latest to:notified] == NSOrderedSame) {
        return surfaced(ingested);
    }

    if (soakDuration == CDRSoakDurationOff) {
        return surfaced(notifiedState);
    }

    // Maturity keys on the *current* resolved setting each check — changing
    // the deferral (in Settings or for this app) retroactively re-gates.
    NSDate *firstSeen = ingested.firstSeenByVersion[latest];
    NSTimeInterval soak = CDRSoakDurationInterval(soakDuration);
    if ([now timeIntervalSinceDate:firstSeen] >= soak) {
        return surfaced(notifiedState);
    }

    // Soaking. A break-through offers it honestly but does NOT mark it
    // notified — only the user's install consent does (deferral.md).
    NSDate *deferredUntil = [firstSeen dateByAddingTimeInterval:soak];
    return decision(breakThrough ? CDRUpdateOutcomeDeferredOffered : CDRUpdateOutcomeDeferred,
                    deferredUntil, nil, ingested);
}

@end

#pragma mark - Copy

NSString *CDRUpdateGateReasonCopy(CDRUpdateDecision *decision, NSString *installedVersion, NSString *version) {
    NSString *held = nil;
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        if (CDRReleaseNoteTypeSetContains(decision.heldTypes, (CDRReleaseNoteType)i)) {
            // Name the first held type in the fixed order.
            held = [NSString stringWithFormat:@"includes %@", CDRReleaseNoteTypeNounPhrase((CDRReleaseNoteType)i)];
            break;
        }
    }
    if (decision.stoppedAtMajor) {
        NSString *major = [NSString stringWithFormat:@"%@ is a major version; you stop at major versions, so %@ stays installed until you choose.",
                           version, installedVersion];
        return held ? [major stringByAppendingFormat:@" It also %@.", held] : major;
    }
    return held ? [NSString stringWithFormat:@"Held because it %@.", held] : @"Held for manual install.";
}

NSString *CDRUrgencyNoticeCopy(CDRUrgency urgency, NSString *appName, NSString *version) {
    NSString *reason = nil;
    switch (urgency) {
        case CDRUrgencyNone: return @"";
        case CDRUrgencySystemRisk: reason = @"a vulnerability that puts the system at risk"; break;
        case CDRUrgencyDataLoss: reason = @"a bug that can cause data loss"; break;
        case CDRUrgencyDataExfiltration: reason = @"a potential data exfiltration issue"; break;
    }
    return [NSString stringWithFormat:@"The developer has flagged %@ %@ as fixing %@.",
            appName, version, reason];
}

NSString *CDRDeferredOfferCopy(NSString *appName, NSString *version, NSDate *deferredUntil) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [NSString stringWithFormat:@"%@ %@ is available (deferred until %@ by your update settings). Install anyway?",
            appName, version, [formatter stringFromDate:deferredUntil]];
}

NSString *CDRRetractedPendingCopy(NSString *appName, NSString *retractedVersion, NSString *installedVersion) {
    return [NSString stringWithFormat:@"%@: the developer retracted update %@. You already have the latest build (%@).",
            appName, retractedVersion, installedVersion];
}

NSString *CDRRetractedInstalledCopy(NSString *appName, NSString *retractedVersion) {
    return [NSString stringWithFormat:@"%@: the developer recalled build %@, which you have installed. "
            @"Conductor does not downgrade automatically — check the developer's site for guidance.",
            appName, retractedVersion];
}
