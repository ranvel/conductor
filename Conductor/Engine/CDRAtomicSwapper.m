//
//  CDRAtomicSwapper.m
//  Conductor
//

#import "CDRAtomicSwapper.h"
#import "CDRErrors.h"
#import <AppKit/AppKit.h>

@implementation CDRAtomicSwapper

static BOOL IsPermissionError(NSError *error) {
    for (NSError *e = error; e; e = e.userInfo[NSUnderlyingErrorKey]) {
        if ([e.domain isEqualToString:NSPOSIXErrorDomain] &&
            (e.code == EPERM || e.code == EACCES)) return YES;
        if ([e.domain isEqualToString:NSCocoaErrorDomain] &&
            (e.code == NSFileWriteNoPermissionError || e.code == NSFileWriteVolumeReadOnlyError)) return YES;
    }
    return NO;
}

- (BOOL)swapInstalledAppAtURL:(NSURL *)installedURL
           withStagedAppAtURL:(NSURL *)stagedURL
                     bundleID:(NSString *)bundleID
                    backupURL:(NSURL **)backupOut
                        error:(NSError **)error {
    NSString *backupName = [NSString stringWithFormat:@"%@.conductor-displaced-%@",
                            installedURL.lastPathComponent, NSUUID.UUID.UUIDString];
    NSURL *resultingURL = nil;
    NSError *replaceError = nil;
    BOOL ok = [[NSFileManager defaultManager]
        replaceItemAtURL:installedURL
           withItemAtURL:stagedURL
          backupItemName:backupName
                 options:(NSFileManagerItemReplacementUsingNewMetadataOnly |
                          NSFileManagerItemReplacementWithoutDeletingBackupItem)
        resultingItemURL:&resultingURL
                   error:&replaceError];
    if (!ok) {
        CDRErrorCode code = IsPermissionError(replaceError) ? CDRErrorPermissionDenied
                                                            : CDRErrorSwapFailed;
        if (error) *error = CDRError(code, bundleID, replaceError, nil);
        return NO;
    }

    if (backupOut) {
        // replaceItemAtURL puts the backup next to the original, named backupItemName.
        NSURL *backup = [installedURL.URLByDeletingLastPathComponent
                         URLByAppendingPathComponent:backupName];
        *backupOut = [[NSFileManager defaultManager] fileExistsAtPath:backup.path] ? backup : nil;
    }
    return YES;
}

- (void)trashDisplacedBundleAtURL:(NSURL *)backupURL
                       completion:(void (^)(NSError *_Nullable))completion {
    [[NSWorkspace sharedWorkspace] recycleURLs:@[backupURL]
                             completionHandler:^(NSDictionary<NSURL *, NSURL *> *newURLs, NSError *error) {
        completion(error);
    }];
}

@end
