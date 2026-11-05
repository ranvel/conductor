//
//  CDRBundleInspector.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRNetworkInspection.h"

NS_ASSUME_NONNULL_BEGIN

/// Reads things Conductor *shows* about a bundle. Nothing here is a
/// verification input: CDRCodeSignature stays the security perimeter, and a
/// value read here never decides whether a build is installable.
@interface CDRBundleInspector : NSObject

/// The organization on the bundle's signing certificate ("Cedar Syntax LLC"),
/// for display beside the app's name. Nil for unsigned or ad-hoc bundles, or
/// when the certificate names no organization.
+ (nullable NSString *)developerNameForBundleAtURL:(NSURL *)url;

/// The bundle's entitlements, from its code signature — never from a file
/// beside it. An empty dictionary for a signed bundle that declares none;
/// nil when there is no signature to read them from. `outTeamID` receives
/// the signing Team ID when there is one.
///
/// This does not validate anything. For a staged build, call it only after
/// CDRCodeSignature has validated that same bundle (the update operation's
/// Inspect step runs after Verify for exactly this reason).
+ (nullable NSDictionary *)entitlementsForBundleAtURL:(NSURL *)url
                                               teamID:(NSString * _Nullable * _Nullable)outTeamID;

/// The posture those entitlements describe; Unknown when they can't be read.
+ (CDRNetworkPosture)networkPostureForBundleAtURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
