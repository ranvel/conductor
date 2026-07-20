//
//  CDRAtomicSwapperTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRAtomicSwapper.h"
#import "CDRErrors.h"

@interface CDRAtomicSwapperTests : XCTestCase
@property (nonatomic) NSURL *root;
@end

@implementation CDRAtomicSwapperTests

- (void)setUp {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDRAtomicSwapperTests-%@", NSUUID.UUID.UUIDString]];
    self.root = [NSURL fileURLWithPath:path isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.root
                             withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
}

- (NSURL *)makeBundleNamed:(NSString *)name marker:(NSString *)marker {
    NSURL *bundle = [self.root URLByAppendingPathComponent:name];
    NSURL *contents = [bundle URLByAppendingPathComponent:@"Contents"];
    [[NSFileManager defaultManager] createDirectoryAtURL:contents
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [[marker dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:[contents URLByAppendingPathComponent:@"marker.txt"] atomically:YES];
    return bundle;
}

static NSString *MarkerIn(NSURL *bundle) {
    NSData *data = [NSData dataWithContentsOfURL:
        [bundle URLByAppendingPathComponent:@"Contents/marker.txt"]];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (void)testSwapExchangesContentAndPreservesBackup {
    NSURL *installed = [self makeBundleNamed:@"Installed.app" marker:@"OLD"];
    NSURL *staged = [self makeBundleNamed:@"Staged.app" marker:@"NEW"];

    CDRAtomicSwapper *swapper = [[CDRAtomicSwapper alloc] init];
    NSURL *backup = nil;
    NSError *error = nil;
    BOOL ok = [swapper swapInstalledAppAtURL:installed
                          withStagedAppAtURL:staged
                                    bundleID:@"com.example.testee"
                                   backupURL:&backup
                                       error:&error];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertEqualObjects(MarkerIn(installed), @"NEW", @"installed path now carries the new content");
    XCTAssertNotNil(backup, @"displaced bundle preserved");
    XCTAssertEqualObjects(MarkerIn(backup), @"OLD", @"backup is the old content");
}

- (void)testFailedSwapLeavesInstalledUntouched {
    NSURL *installed = [self makeBundleNamed:@"Installed.app" marker:@"OLD"];
    NSURL *missingStaged = [self.root URLByAppendingPathComponent:@"DoesNotExist.app"];

    CDRAtomicSwapper *swapper = [[CDRAtomicSwapper alloc] init];
    NSError *error = nil;
    BOOL ok = [swapper swapInstalledAppAtURL:installed
                          withStagedAppAtURL:missingStaged
                                    bundleID:@"com.example.testee"
                                   backupURL:NULL
                                       error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqualObjects(error.domain, CDRErrorDomain);
    XCTAssertEqualObjects(MarkerIn(installed), @"OLD", @"installed bundle untouched after failure");
}

@end
