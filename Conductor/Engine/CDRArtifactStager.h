//
//  CDRArtifactStager.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Staging directory management and artifact extraction (replace-flow.md §2).
///
/// Staging lives NEXT TO the destination
/// (`/Applications/.conductor-staging/<bundle-id>/`) so the final rename is on
/// the same APFS volume by construction — NSTemporaryDirectory() is not
/// guaranteed to qualify, and a cross-volume "rename" silently becomes a
/// non-atomic copy.
@interface CDRArtifactStager : NSObject

/// Creates (or empties) the staging directory for a bundle ID.
- (nullable NSURL *)createStagingDirectoryForBundleID:(NSString *)bundleID
                                      nearDestination:(NSURL *)destinationURL
                                                error:(NSError **)error;

/// Extracts the artifact into staging and returns the URL of the single .app
/// bundle found inside. Detects format by content: zip magic ("PK\x03\x04")
/// → ditto -xk; anything else is handed to hdiutil (attach -nobrowse
/// -readonly), the .app copied out preserving xattrs (quarantine expected and
/// deliberately kept — it is stripped only after verification passes), then
/// detached.
- (nullable NSURL *)extractArtifactAtURL:(NSURL *)artifactURL
                      toStagingDirectory:(NSURL *)stagingURL
                                bundleID:(nullable NSString *)bundleID
                                   error:(NSError **)error;

/// Removes the staging directory for a bundle ID, if present. Never fails
/// loudly — cleanup is best-effort.
- (void)removeStagingDirectoryForBundleID:(NSString *)bundleID
                          nearDestination:(NSURL *)destinationURL;

/// Root staging container for a destination directory
/// (e.g. /Applications/.conductor-staging).
+ (NSURL *)stagingRootNearDestination:(NSURL *)destinationURL;

@end

NS_ASSUME_NONNULL_END
