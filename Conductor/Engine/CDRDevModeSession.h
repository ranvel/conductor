//
//  CDRDevModeSession.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const CDRDevModeArgument; // @"--dev-mode"

/// The session's transport/visibility policy, decided once at launch from the
/// process arguments and never persisted (dev-mode.md: session-only by
/// construction — there is no defaults key to leak into the next launch).
///
/// Normal session: all managed apps visible, HTTPS required everywhere.
/// Dev-mode session (`conductor --dev-mode <bundle-id>`): exactly one app
/// visible, and for that app only, plain-HTTP URLs are permitted. Transport is
/// the ONLY thing dev mode relaxes — verification is untouched.
@interface CDRDevModeSession : NSObject

@property (nonatomic, readonly) BOOL devModeEnabled;
@property (nonatomic, readonly, nullable) NSString *devModeBundleID;

/// Parses launch arguments. `--dev-mode` requires exactly one following
/// bundle-id operand; a repeated flag or missing operand is an error, not a
/// feature. Arguments without the flag yield a normal session.
+ (nullable instancetype)sessionFromArguments:(NSArray<NSString *> *)arguments
                                        error:(NSError **)error;

/// Dev mode shows only the named app; normal mode shows everything.
- (BOOL)isBundleVisible:(NSString *)bundleID;

/// The single place HTTP is ever permitted. Consulted per-URL by the manifest
/// fetcher and the artifact downloader.
- (BOOL)allowsURL:(NSURL *)url forBundleID:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
