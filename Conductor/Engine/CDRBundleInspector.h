//
//  CDRBundleInspector.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads things Conductor *shows* about a bundle. Nothing here is a
/// verification input: CDRCodeSignature stays the security perimeter, and a
/// value read here never decides whether a build is installable.
@interface CDRBundleInspector : NSObject

/// The organization on the bundle's signing certificate ("Cedar Syntax LLC"),
/// for display beside the app's name. Nil for unsigned or ad-hoc bundles, or
/// when the certificate names no organization.
+ (nullable NSString *)developerNameForBundleAtURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
