//
//  CDRNetworkInspection.m
//  Conductor
//

#import "CDRNetworkInspection.h"
#import "CDRInternetAccessPolicy.h"
#import "CDRUpdatePreferences.h"

NSString * const CDREntitlementAppSandbox = @"com.apple.security.app-sandbox";
NSString * const CDREntitlementNetworkClient = @"com.apple.security.network.client";
NSString * const CDREntitlementNetworkServer = @"com.apple.security.network.server";

/// An entitlement counts only as a real boolean true.
static BOOL EntitlementIsTrue(NSDictionary *entitlements, NSString *key) {
    id value = entitlements[key];
    return [value isKindOfClass:[NSNumber class]] && [value boolValue];
}

CDRNetworkPosture CDRNetworkPostureFromEntitlements(NSDictionary *entitlements) {
    if (!EntitlementIsTrue(entitlements, CDREntitlementAppSandbox)) return CDRNetworkPostureUnrestricted;
    BOOL client = EntitlementIsTrue(entitlements, CDREntitlementNetworkClient);
    BOOL server = EntitlementIsTrue(entitlements, CDREntitlementNetworkServer);
    if (client && server) return CDRNetworkPostureBoth;
    if (client) return CDRNetworkPostureClient;
    if (server) return CDRNetworkPostureServer;
    return CDRNetworkPostureNone;
}

BOOL CDRNetworkPostureHasAccess(CDRNetworkPosture posture) {
    switch (posture) {
        case CDRNetworkPostureClient:
        case CDRNetworkPostureServer:
        case CDRNetworkPostureBoth:
        case CDRNetworkPostureUnrestricted:
            return YES;
        case CDRNetworkPostureNone:
        case CDRNetworkPostureUnknown:
            return NO;
    }
    return NO;
}

NSString *CDRNetworkPostureDisplayName(CDRNetworkPosture posture) {
    switch (posture) {
        case CDRNetworkPostureUnknown: return @"Unknown";
        case CDRNetworkPostureNone: return @"No network access";
        case CDRNetworkPostureClient: return @"Outgoing connections";
        case CDRNetworkPostureServer: return @"Incoming connections";
        case CDRNetworkPostureBoth: return @"Outgoing and incoming connections";
        case CDRNetworkPostureUnrestricted: return @"Not sandboxed";
    }
    return @"Unknown";
}

CDRNetworkChange CDRNetworkChangeBetween(CDRNetworkPosture installed, CDRNetworkPosture staged) {
    // "Gained" errs toward asking: an installed posture that can't be read
    // isn't proof of access, and a staged one that can't be read isn't
    // proof of none.
    BOOL installedMayLackAccess = (installed == CDRNetworkPostureNone || installed == CDRNetworkPostureUnknown);
    BOOL stagedMayHaveAccess = CDRNetworkPostureHasAccess(staged) || staged == CDRNetworkPostureUnknown;
    if (installedMayLackAccess && stagedMayHaveAccess) {
        // Both unreadable tells us nothing changed that we can name.
        if (installed == CDRNetworkPostureUnknown && staged == CDRNetworkPostureUnknown) return CDRNetworkChangeNone;
        return CDRNetworkChangeGained;
    }
    // "Lost" needs proof on both sides.
    if (CDRNetworkPostureHasAccess(installed) && staged == CDRNetworkPostureNone) return CDRNetworkChangeLost;
    return CDRNetworkChangeNone;
}

@implementation CDRNetworkInspection

- (instancetype)initWithInstalledVersion:(NSString *)installedVersion
                           stagedVersion:(NSString *)stagedVersion
                   installedEntitlements:(NSDictionary *)installedEntitlements
                      stagedEntitlements:(NSDictionary *)stagedEntitlements
                            stagedPolicy:(CDRInternetAccessPolicy *)stagedPolicy
                                  teamID:(NSString *)teamID {
    self = [super init];
    if (!self) return nil;
    _installedVersion = [installedVersion copy];
    _stagedVersion = [stagedVersion copy];
    _installedPosture = installedEntitlements ? CDRNetworkPostureFromEntitlements(installedEntitlements)
                                              : CDRNetworkPostureUnknown;
    _stagedPosture = stagedEntitlements ? CDRNetworkPostureFromEntitlements(stagedEntitlements)
                                        : CDRNetworkPostureUnknown;
    _stagedPolicy = stagedPolicy;
    _teamID = [teamID copy];

    NSMutableArray<NSString *> *added = [NSMutableArray array];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    for (NSString *key in @[CDREntitlementAppSandbox, CDREntitlementNetworkClient, CDREntitlementNetworkServer]) {
        BOOL before = installedEntitlements && EntitlementIsTrue(installedEntitlements, key);
        BOOL after = stagedEntitlements && EntitlementIsTrue(stagedEntitlements, key);
        if (after && !before) [added addObject:key];
        if (before && !after) [removed addObject:key];
    }
    _addedEntitlements = [added copy];
    _removedEntitlements = [removed copy];
    return self;
}

- (CDRNetworkChange)change {
    return CDRNetworkChangeBetween(self.installedPosture, self.stagedPosture);
}

- (BOOL)hasPolicy {
    return self.stagedPolicy.rows.count > 0;
}

@end

@implementation CDRNetworkGate

+ (CDRNetworkGateDecision)decisionForInstalledPosture:(CDRNetworkPosture)installed
                                        stagedPosture:(CDRNetworkPosture)staged
                                            hasPolicy:(BOOL)hasPolicy
                                          preferences:(CDRUpdatePreferences *)preferences {
    if (!preferences.requireNetworkApproval) return CDRNetworkGateDecisionNoAsk;
    if (CDRNetworkChangeBetween(installed, staged) != CDRNetworkChangeGained) return CDRNetworkGateDecisionNoAsk;
    if (!hasPolicy) return CDRNetworkGateDecisionAskWithoutPolicy;
    // The build says where it connects and why. Either that is enough for
    // the user, or they want to read it first.
    return preferences.policyExemptsApproval ? CDRNetworkGateDecisionNoAsk : CDRNetworkGateDecisionAskWithPolicy;
}

+ (CDRNetworkGateDecision)decisionForInspection:(CDRNetworkInspection *)inspection
                                    preferences:(CDRUpdatePreferences *)preferences {
    return [self decisionForInstalledPosture:inspection.installedPosture
                               stagedPosture:inspection.stagedPosture
                                   hasPolicy:inspection.hasPolicy
                                 preferences:preferences];
}

@end
