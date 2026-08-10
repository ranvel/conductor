//
//  CDRHelperProtocol.h
//  Conductor
//

#import <Foundation/Foundation.h>

/// XPC protocol for the privileged helper daemon. Exactly one operation:
/// atomically swap a verified staged bundle into place at the installed path.
/// The helper runs as root (LaunchDaemon); Conductor handles all verification.
@protocol CDRHelperProtocol <NSObject>

- (void)swapBundleAtPath:(NSString *)installedPath
         withStagedAtPath:(NSString *)stagedPath
                withReply:(void (^)(BOOL success, NSString * _Nullable backupPath,
                                    NSString * _Nullable errorMessage))reply;

@end
