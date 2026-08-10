//
//  CDRPrivilegedHelperManager.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages the privileged helper daemon lifecycle (SMAppService registration)
/// and XPC communication. The helper runs as root and performs the atomic swap
/// when the unprivileged swap fails with EPERM.
@interface CDRPrivilegedHelperManager : NSObject

+ (instancetype)sharedManager;

/// Whether the helper daemon is registered and enabled.
@property (nonatomic, readonly) BOOL isHelperInstalled;

/// Registers the helper via SMAppService. Opens System Settings if user
/// approval is required. Returns NO with error on failure.
- (BOOL)installHelperWithError:(NSError **)error;

/// Unregisters the helper daemon.
- (BOOL)uninstallHelperWithError:(NSError **)error;

/// Atomically swaps the installed bundle with the staged one via the root
/// helper. On success, backupURL is the displaced old bundle (for trashing).
- (void)swapBundleAtURL:(NSURL *)installedURL
        withStagedAtURL:(NSURL *)stagedURL
             completion:(void (^)(BOOL success, NSURL * _Nullable backupURL,
                                  NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
