//
//  CDRUpdatePolicy.m
//  Conductor
//

#import "CDRUpdatePolicy.h"
#import "CDRAppRegistration.h"
#import "CDRAppUpdateState.h"
#import "CDRVersion.h"

NSString * const CDRSoakDurationDefaultsKey = @"CDRSoakDuration";

NSTimeInterval CDRSoakDurationInterval(CDRSoakDuration duration) {
    switch (duration) {
        case CDRSoakDurationOff: return 0;
        case CDRSoakDurationOneDay: return 24.0 * 60.0 * 60.0;
        case CDRSoakDurationOneWeek: return 7.0 * 24.0 * 60.0 * 60.0;
    }
    return 0;
}

CDRSoakDuration CDRSoakDurationFromDefaultsToken(NSString *token) {
    if ([token isKindOfClass:[NSString class]]) {
        if ([token isEqualToString:@"1d"]) return CDRSoakDurationOneDay;
        if ([token isEqualToString:@"1w"]) return CDRSoakDurationOneWeek;
    }
    return CDRSoakDurationOff;
}

NSString *CDRSoakDurationDefaultsToken(CDRSoakDuration duration) {
    switch (duration) {
        case CDRSoakDurationOff: return @"off";
        case CDRSoakDurationOneDay: return @"1d";
        case CDRSoakDurationOneWeek: return @"1w";
    }
    return @"off";
}

#pragma mark - Decision

@interface CDRUpdateDecision ()
- (instancetype)initWithOutcome:(CDRUpdateOutcome)outcome
                  deferredUntil:(NSDate *)deferredUntil
               retractedVersion:(NSString *)retractedVersion
                        urgency:(CDRUrgency)urgency
                stateAfterCheck:(CDRAppUpdateState *)stateAfterCheck;
@end

@implementation CDRUpdateDecision

- (instancetype)initWithOutcome:(CDRUpdateOutcome)outcome
                  deferredUntil:(NSDate *)deferredUntil
               retractedVersion:(NSString *)retractedVersion
                        urgency:(CDRUrgency)urgency
                stateAfterCheck:(CDRAppUpdateState *)stateAfterCheck {
    self = [super init];
    if (self) {
        _outcome = outcome;
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
                                  soakDuration:(CDRSoakDuration)soakDuration
                                  breakThrough:(BOOL)breakThrough
                                           now:(NSDate *)now {
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
        return decision(CDRUpdateOutcomeAvailable, nil, nil, notifiedState);
    }

    // Already surfaced: re-show without re-gating on soak (and without
    // refreshing notified_at — the promise was already made).
    if (notified && [CDRVersion compare:latest to:notified] == NSOrderedSame) {
        return decision(CDRUpdateOutcomeAvailable, nil, nil, ingested);
    }

    if (soakDuration == CDRSoakDurationOff) {
        return decision(CDRUpdateOutcomeAvailable, nil, nil, notifiedState);
    }

    // Maturity keys on the *current* setting each check — changing the global
    // soak retroactively re-gates, the correct reading of "one global value."
    NSDate *firstSeen = ingested.firstSeenByVersion[latest];
    NSTimeInterval soak = CDRSoakDurationInterval(soakDuration);
    if ([now timeIntervalSinceDate:firstSeen] >= soak) {
        return decision(CDRUpdateOutcomeAvailable, nil, nil, notifiedState);
    }

    // Soaking. A break-through offers it honestly but does NOT mark it
    // notified — only the user's install consent does (deferral.md).
    NSDate *deferredUntil = [firstSeen dateByAddingTimeInterval:soak];
    return decision(breakThrough ? CDRUpdateOutcomeDeferredOffered : CDRUpdateOutcomeDeferred,
                    deferredUntil, nil, ingested);
}

@end

#pragma mark - Copy

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
