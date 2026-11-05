//
//  CDRNetworkInspection.h
//  Conductor
//
//  What a bundle is *allowed* to do on the network, read from its code
//  signature, and the pure rule that decides whether a new build's change
//  needs the user's approval.
//
//  This is a consent input, never a verification input. A build that passes
//  Verify is installable; nothing here can refuse one, and nothing here is
//  consulted before Verify has passed.
//

#import <Foundation/Foundation.h>

@class CDRUpdatePreferences;
@class CDRInternetAccessPolicy;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const CDREntitlementAppSandbox;      // com.apple.security.app-sandbox
extern NSString * const CDREntitlementNetworkClient;   // com.apple.security.network.client
extern NSString * const CDREntitlementNetworkServer;   // com.apple.security.network.server

/// A bundle's network posture, from its entitlements.
typedef NS_ENUM(NSInteger, CDRNetworkPosture) {
    /// The signature could not be read (unsigned, damaged). Never "no access".
    CDRNetworkPostureUnknown = 0,
    /// Sandboxed with neither network entitlement: the OS will not let it
    /// open a socket.
    CDRNetworkPostureNone,
    /// Sandboxed, outgoing connections.
    CDRNetworkPostureClient,
    /// Sandboxed, incoming connections.
    CDRNetworkPostureServer,
    CDRNetworkPostureBoth,
    /// Not sandboxed: nothing restricts its network use. Only a fully
    /// sandboxed app can be said to have no access.
    CDRNetworkPostureUnrestricted,
};

/// The posture a signed bundle's entitlements describe. `entitlements` is
/// the dictionary from its signature; empty means "signed, none declared".
CDRNetworkPosture CDRNetworkPostureFromEntitlements(NSDictionary *entitlements);

/// YES for Client, Server, Both and Unrestricted.
BOOL CDRNetworkPostureHasAccess(CDRNetworkPosture posture);

/// "No network access", "Outgoing connections", "Not sandboxed", …
NSString *CDRNetworkPostureDisplayName(CDRNetworkPosture posture);

/// How a new build's posture differs from the installed one's.
typedef NS_ENUM(NSInteger, CDRNetworkChange) {
    CDRNetworkChangeNone = 0,
    /// From provably no access to access (or to a posture that can't be
    /// read). The only change that can need approval.
    CDRNetworkChangeGained,
    /// From access to provably none. Good news: shown, never asked about.
    CDRNetworkChangeLost,
};

CDRNetworkChange CDRNetworkChangeBetween(CDRNetworkPosture installed, CDRNetworkPosture staged);

typedef NS_ENUM(NSInteger, CDRNetworkGateDecision) {
    CDRNetworkGateDecisionNoAsk = 0,
    /// Ask, with the developer's Internet Access Policy shown. Approve is safe.
    CDRNetworkGateDecisionAskWithPolicy,
    /// Ask; the build doesn't say why. Skip is safe.
    CDRNetworkGateDecisionAskWithoutPolicy,
};

/// What Conductor learned about a verified, staged build next to the
/// installed one. Immutable.
@interface CDRNetworkInspection : NSObject

@property (nonatomic, readonly, copy) NSString *installedVersion;
@property (nonatomic, readonly, copy) NSString *stagedVersion;
@property (nonatomic, readonly) CDRNetworkPosture installedPosture;
@property (nonatomic, readonly) CDRNetworkPosture stagedPosture;
/// The staged build's Internet Access Policy, when it ships a usable one.
@property (nonatomic, readonly, nullable) CDRInternetAccessPolicy *stagedPolicy;
/// The three entitlements above that the staged build has and the installed
/// one doesn't, and the reverse — the sheet's "+ …" / "− …" lines.
@property (nonatomic, readonly, copy) NSArray<NSString *> *addedEntitlements;
@property (nonatomic, readonly, copy) NSArray<NSString *> *removedEntitlements;
/// The Team ID both builds are signed with (Verify already pinned it).
@property (nonatomic, readonly, copy, nullable) NSString *teamID;

@property (nonatomic, readonly) CDRNetworkChange change;
/// YES when the staged build ships a policy with at least one row to show.
@property (nonatomic, readonly) BOOL hasPolicy;

- (instancetype)initWithInstalledVersion:(NSString *)installedVersion
                           stagedVersion:(NSString *)stagedVersion
                   installedEntitlements:(nullable NSDictionary *)installedEntitlements
                      stagedEntitlements:(nullable NSDictionary *)stagedEntitlements
                            stagedPolicy:(nullable CDRInternetAccessPolicy *)stagedPolicy
                                  teamID:(nullable NSString *)teamID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface CDRNetworkGate : NSObject

/// The rule, pure: ask only when the gate is on and access is gained; a
/// shipped policy either exempts the update or is shown, by the user's choice.
+ (CDRNetworkGateDecision)decisionForInstalledPosture:(CDRNetworkPosture)installed
                                        stagedPosture:(CDRNetworkPosture)staged
                                            hasPolicy:(BOOL)hasPolicy
                                          preferences:(CDRUpdatePreferences *)preferences;

+ (CDRNetworkGateDecision)decisionForInspection:(CDRNetworkInspection *)inspection
                                    preferences:(CDRUpdatePreferences *)preferences;

@end

NS_ASSUME_NONNULL_END
