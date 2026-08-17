//
//  CDRAppRegistration.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One managed app: its installed identity plus the URLs declared in the
/// conductor.json embedded at Contents/Resources/conductor.json. Because that
/// file lives inside the signed bundle, it is covered by the vendor's code
/// seal — it cannot be tampered with without breaking the signature the next
/// update verifies against.
@interface CDRAppRegistration : NSObject

@property (nonatomic, readonly) NSURL *appURL;
@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly) NSString *installedShortVersion;   // CFBundleShortVersionString
@property (nonatomic, readonly, nullable) NSString *installedBuildVersion; // CFBundleVersion
@property (nonatomic, readonly) NSURL *updateURL;
@property (nonatomic, readonly, nullable) NSURL *fallbackURL;
@property (nonatomic, readonly, nullable) NSURL *vendorURL;

/// Reads Info.plist and conductor.json from the bundle at appURL.
/// Returns nil (with error) if the bundle has no conductor.json, the JSON is
/// malformed, the format version is unsupported, or identity keys are missing.
+ (nullable instancetype)registrationForAppAtURL:(NSURL *)appURL error:(NSError **)error;

/// Relative path of the marker file inside a bundle ("Contents/Resources/conductor.json").
+ (NSString *)conductorJSONRelativePath;

/// Copy with the given installed versions; every other field (URLs, bundle ID,
/// appURL) carried over. Used to push the post-swap version without touching disk.
- (instancetype)registrationWithInstalledShortVersion:(NSString *)shortVersion
                                         buildVersion:(nullable NSString *)buildVersion;

/// Fresh copy with the installed versions re-read from Contents/Info.plist on
/// disk (never NSBundle — it caches per path for the process lifetime).
/// Returns self (pointer-identical) if the plist is unreadable, the bundle ID
/// no longer matches (app removed or replaced out-of-band), or nothing changed
/// — callers can use pointer equality as a cheap "did it change" test.
- (instancetype)registrationByRefreshingInstalledVersion;

@end

NS_ASSUME_NONNULL_END
