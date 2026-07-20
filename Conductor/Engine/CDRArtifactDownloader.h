//
//  CDRArtifactDownloader.h
//  Conductor
//

#import <Foundation/Foundation.h>

@class CDRDevModeSession;

NS_ASSUME_NONNULL_BEGIN

/// Downloads the update artifact into the staging directory (same volume as
/// the destination, unified cleanup). Optionally verifies a SHA-256 from the
/// manifest — an integrity hint against truncation/corruption, not a security
/// boundary (the manifest is unauthenticated; the real check is Team ID
/// pinning on the extracted bundle).
@interface CDRArtifactDownloader : NSObject

- (instancetype)initWithSession:(CDRDevModeSession *)session;

- (void)downloadArtifactAtURL:(NSURL *)url
                  forBundleID:(NSString *)bundleID
           toStagingDirectory:(NSURL *)stagingURL
               expectedSHA256:(nullable NSString *)sha256
                     progress:(nullable void (^)(double fractionCompleted))progress
                   completion:(void (^)(NSURL *_Nullable fileURL,
                                        NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
