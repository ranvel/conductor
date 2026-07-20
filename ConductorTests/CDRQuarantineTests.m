//
//  CDRQuarantineTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import <sys/xattr.h>
#import "CDRQuarantine.h"

@interface CDRQuarantineTests : XCTestCase
@property (nonatomic) NSURL *root;
@end

@implementation CDRQuarantineTests

- (void)setUp {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDRQuarantineTests-%@", NSUUID.UUID.UUIDString]];
    self.root = [NSURL fileURLWithPath:path isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.root
                             withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
}

static void SetQuarantine(NSURL *url) {
    const char *value = "0083;5f000000;Safari;";
    setxattr(url.fileSystemRepresentation, "com.apple.quarantine", value, strlen(value), 0, XATTR_NOFOLLOW);
}

- (NSURL *)makeFileAt:(NSString *)relative {
    NSURL *url = [self.root URLByAppendingPathComponent:relative];
    [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSData data] writeToURL:url atomically:YES];
    return url;
}

- (void)testStripsQuarantineFromTree {
    NSURL *f1 = [self makeFileAt:@"Contents/MacOS/binary"];
    NSURL *f2 = [self makeFileAt:@"Contents/Resources/.hidden"];
    NSURL *dir = [self.root URLByAppendingPathComponent:@"Contents"];
    SetQuarantine(self.root);
    SetQuarantine(f1);
    SetQuarantine(f2);
    SetQuarantine(dir);

    XCTAssertTrue([CDRQuarantine treeContainsQuarantineAtURL:self.root]);

    NSError *error = nil;
    XCTAssertTrue([CDRQuarantine stripQuarantineRecursivelyAtURL:self.root error:&error], @"%@", error);
    XCTAssertFalse([CDRQuarantine treeContainsQuarantineAtURL:self.root]);
}

- (void)testSymlinkTargetIsNotTouched {
    // A quarantined file OUTSIDE the tree, pointed to by a symlink INSIDE it,
    // must keep its attribute (XATTR_NOFOLLOW).
    NSURL *outside = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"outside-%@", NSUUID.UUID.UUIDString]]];
    [[NSData data] writeToURL:outside atomically:YES];
    SetQuarantine(outside);

    NSURL *link = [self.root URLByAppendingPathComponent:@"link"];
    [[NSFileManager defaultManager] createSymbolicLinkAtURL:link
                                         withDestinationURL:outside error:NULL];
    SetQuarantine(link);

    XCTAssertTrue([CDRQuarantine stripQuarantineRecursivelyAtURL:self.root error:NULL]);
    XCTAssertFalse([CDRQuarantine treeContainsQuarantineAtURL:self.root]);
    // The target still carries the attribute.
    XCTAssertTrue(getxattr(outside.fileSystemRepresentation, "com.apple.quarantine", NULL, 0, 0, XATTR_NOFOLLOW) >= 0);
    [[NSFileManager defaultManager] removeItemAtURL:outside error:NULL];
}

- (void)testCleanTreeIsANoOp {
    [self makeFileAt:@"Contents/MacOS/binary"];
    NSError *error = nil;
    XCTAssertTrue([CDRQuarantine stripQuarantineRecursivelyAtURL:self.root error:&error]);
    XCTAssertNil(error);
}

@end
