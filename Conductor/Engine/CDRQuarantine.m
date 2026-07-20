//
//  CDRQuarantine.m
//  Conductor
//

#import "CDRQuarantine.h"
#import <sys/xattr.h>

static const char *kQuarantineAttr = "com.apple.quarantine";

@implementation CDRQuarantine

+ (BOOL)stripQuarantineRecursivelyAtURL:(NSURL *)rootURL error:(NSError **)error {
    __block NSError *firstFailure = nil;

    BOOL (^stripOne)(NSURL *) = ^BOOL(NSURL *url) {
        // XATTR_NOFOLLOW: operate on symlinks themselves, never their targets.
        int rc = removexattr(url.fileSystemRepresentation, kQuarantineAttr, XATTR_NOFOLLOW);
        if (rc == 0 || errno == ENOATTR) return YES;
        if (!firstFailure) {
            firstFailure = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{
                NSFilePathErrorKey: url.path,
            }];
        }
        return NO;
    };

    if (!stripOne(rootURL)) {
        if (error) *error = firstFailure;
        return NO;
    }

    // Hidden files included, package contents included, symlinks not followed
    // (NSDirectoryEnumerator does not follow symlinks by default).
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [[NSFileManager defaultManager] enumeratorAtURL:rootURL
                             includingPropertiesForKeys:nil
                                                options:0
                                           errorHandler:nil];
    for (NSURL *item in enumerator) {
        stripOne(item);
    }

    if (firstFailure) {
        if (error) *error = firstFailure;
        return NO;
    }
    return YES;
}

+ (BOOL)treeContainsQuarantineAtURL:(NSURL *)rootURL {
    BOOL (^hasAttr)(NSURL *) = ^BOOL(NSURL *url) {
        return getxattr(url.fileSystemRepresentation, kQuarantineAttr, NULL, 0, 0, XATTR_NOFOLLOW) >= 0;
    };
    if (hasAttr(rootURL)) return YES;
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [[NSFileManager defaultManager] enumeratorAtURL:rootURL
                             includingPropertiesForKeys:nil
                                                options:0
                                           errorHandler:nil];
    for (NSURL *item in enumerator) {
        if (hasAttr(item)) return YES;
    }
    return NO;
}

@end
