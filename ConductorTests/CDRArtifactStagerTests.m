//
//  CDRArtifactStagerTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRArtifactStager.h"
#import "CDRErrors.h"

@interface CDRArtifactStagerTests : XCTestCase
@property (nonatomic) NSURL *root;
@property (nonatomic) CDRArtifactStager *stager;
@end

@implementation CDRArtifactStagerTests

- (void)setUp {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDRArtifactStagerTests-%@", NSUUID.UUID.UUIDString]];
    self.root = [NSURL fileURLWithPath:path isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.root
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    self.stager = [[CDRArtifactStager alloc] init];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
}

/// Builds a dummy .app directory and returns its URL.
- (NSURL *)makeDummyAppIn:(NSURL *)dir {
    NSURL *app = [dir URLByAppendingPathComponent:@"Dummy.app"];
    NSURL *macos = [app URLByAppendingPathComponent:@"Contents/MacOS"];
    [[NSFileManager defaultManager] createDirectoryAtURL:macos
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [[@"#!/bin/sh\n" dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:[macos URLByAppendingPathComponent:@"Dummy"] atomically:YES];
    return app;
}

- (int)runTool:(NSString *)path arguments:(NSArray<NSString *> *)args {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = args;
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    if (![task launchAndReturnError:NULL]) return -1;
    [task waitUntilExit];
    return task.terminationStatus;
}

- (void)testStagingDirectoryIsCreatedNextToDestination {
    NSURL *destination = [self.root URLByAppendingPathComponent:@"Applications" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:destination
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    NSURL *staging = [self.stager createStagingDirectoryForBundleID:@"com.example.testee"
                                                    nearDestination:destination
                                                              error:&error];
    XCTAssertNotNil(staging, @"%@", error);
    XCTAssertTrue([staging.path hasPrefix:[destination URLByAppendingPathComponent:@".conductor-staging"].path]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:staging.path]);

    [self.stager removeStagingDirectoryForBundleID:@"com.example.testee" nearDestination:destination];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:staging.path]);
}

/// Regression: an installed .app destination exists on disk, so its file URL
/// carries the directory hint (an app bundle IS a directory) — which used to
/// route staging *inside* the bundle the swap was about to replace, and
/// renamex_np refuses to swap a directory with its own descendant (EINVAL).
/// Staging must land next to the bundle, never inside it.
- (void)testStagingRootForAppBundleDestinationIsSiblingNotInside {
    NSURL *apps = [self.root URLByAppendingPathComponent:@"Applications" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:apps
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *bundle = [self makeDummyAppIn:apps];
    // Re-derive the URL the way production sees it: from the on-disk path,
    // which picks up the trailing-slash directory hint that triggered the bug.
    NSURL *destination = [NSURL fileURLWithPath:bundle.path];
    XCTAssertTrue(destination.hasDirectoryPath,
        @"precondition: an existing bundle's URL must carry the directory hint");

    NSURL *stagingRoot = [CDRArtifactStager stagingRootNearDestination:destination];
    XCTAssertEqualObjects(stagingRoot.path,
        [apps URLByAppendingPathComponent:@".conductor-staging"].path);
    XCTAssertFalse([stagingRoot.path hasPrefix:bundle.path],
        @"staging inside the destination bundle makes the atomic swap impossible");
}

- (void)testZipExtractionFindsApp {
    NSURL *sourceDir = [self.root URLByAppendingPathComponent:@"src" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:sourceDir
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [self makeDummyAppIn:sourceDir];

    NSURL *zip = [self.root URLByAppendingPathComponent:@"artifact.zip"];
    int zipStatus = [self runTool:@"/usr/bin/ditto"
                        arguments:@[@"-ck", @"--keepParent",
                                    [sourceDir URLByAppendingPathComponent:@"Dummy.app"].path, zip.path]];
    XCTAssertEqual(zipStatus, 0);

    NSURL *staging = [self.root URLByAppendingPathComponent:@"staging" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:staging
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    NSURL *app = [self.stager extractArtifactAtURL:zip toStagingDirectory:staging
                                          bundleID:@"com.example.testee" error:&error];
    XCTAssertNotNil(app, @"%@", error);
    XCTAssertEqualObjects(app.lastPathComponent, @"Dummy.app");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:
        [app URLByAppendingPathComponent:@"Contents/MacOS/Dummy"].path]);
}

- (void)testDMGExtractionFindsApp {
    NSURL *sourceDir = [self.root URLByAppendingPathComponent:@"dmgsrc" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:sourceDir
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [self makeDummyAppIn:sourceDir];

    NSURL *dmg = [self.root URLByAppendingPathComponent:@"artifact.dmg"];
    int dmgStatus = [self runTool:@"/usr/bin/hdiutil"
                        arguments:@[@"create", @"-srcfolder", sourceDir.path,
                                    @"-volname", @"Dummy", @"-fs", @"APFS",
                                    @"-format", @"UDZO", dmg.path]];
    XCTAssertEqual(dmgStatus, 0);

    NSURL *staging = [self.root URLByAppendingPathComponent:@"staging" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:staging
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    NSURL *app = [self.stager extractArtifactAtURL:dmg toStagingDirectory:staging
                                          bundleID:@"com.example.testee" error:&error];
    XCTAssertNotNil(app, @"%@", error);
    XCTAssertEqualObjects(app.lastPathComponent, @"Dummy.app");
}

- (void)testGarbageArtifactFailsCleanly {
    NSURL *garbage = [self.root URLByAppendingPathComponent:@"garbage.dmg"];
    [[@"this is not a disk image" dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:garbage atomically:YES];

    NSURL *staging = [self.root URLByAppendingPathComponent:@"staging" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:staging
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    NSURL *app = [self.stager extractArtifactAtURL:garbage toStagingDirectory:staging
                                          bundleID:@"com.example.testee" error:&error];
    XCTAssertNil(app);
    XCTAssertEqualObjects(error.domain, CDRErrorDomain);
}

@end
