//
//  CDRManifestFetcher.h
//  Conductor
//

#import <Foundation/Foundation.h>

@class CDRAppRegistration;
@class CDRDevModeSession;
@class CDRManifest;

NS_ASSUME_NONNULL_BEGIN

/// Fetches and parses the update manifest for a registration.
///
/// Rules baked in from the specs:
/// - Caching is disabled; a fresh manifest is load-bearing for the future
///   retraction re-check (retraction.md).
/// - The primary update URL wins, always. The fallback URL is consulted only
///   when the primary is unreachable — never as a second opinion.
/// - Transport policy (HTTPS-only outside dev mode) is enforced here, per-URL.
/// - The manifest's bundle_id must match the registration; mismatch is refused
///   before anything is downloaded.
@interface CDRManifestFetcher : NSObject

- (instancetype)initWithSession:(CDRDevModeSession *)session;

/// Completion is invoked on an arbitrary queue. On failure the error's
/// userInfo carries the vendor URL when the registration declares one.
- (void)fetchManifestForRegistration:(CDRAppRegistration *)registration
                          completion:(void (^)(CDRManifest *_Nullable manifest,
                                               NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
