//
//  CDRAtomicSwapper.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The single mutation of /Applications in the whole flow (replace-flow.md §5):
/// an atomic same-volume replace via NSFileManager, with the displaced bundle
/// preserved and then moved to the Trash (never unlinked — user-recoverable).
@interface CDRAtomicSwapper : NSObject

/// Atomically replaces the installed bundle with the staged one. On success,
/// backupOut (if provided) receives the URL of the displaced old bundle,
/// which the caller must later hand to -trashDisplacedBundleAtURL:completion:.
/// EPERM-family failures map to CDRErrorPermissionDenied with the doc's
/// prescribed message; anything else to CDRErrorSwapFailed. On failure the
/// installed bundle is untouched.
- (BOOL)swapInstalledAppAtURL:(NSURL *)installedURL
           withStagedAppAtURL:(NSURL *)stagedURL
                     bundleID:(NSString *)bundleID
                    backupURL:(NSURL *_Nullable *_Nullable)backupOut
                        error:(NSError **)error;

/// Moves the displaced old bundle to the Trash. Non-fatal by design: on
/// failure the old bundle merely lingers; report as a warning, never roll back.
- (void)trashDisplacedBundleAtURL:(NSURL *)backupURL
                       completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
