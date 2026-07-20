//
//  CDRDevModeSessionTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRDevModeSession.h"

@interface CDRDevModeSessionTests : XCTestCase
@end

@implementation CDRDevModeSessionTests

- (void)testNoArgumentsYieldsNormalSession {
    NSError *error = nil;
    CDRDevModeSession *s = [CDRDevModeSession sessionFromArguments:@[@"/path/to/Conductor"] error:&error];
    XCTAssertNotNil(s);
    XCTAssertFalse(s.devModeEnabled);
    XCTAssertNil(s.devModeBundleID);
}

- (void)testSingleDevModeArgument {
    CDRDevModeSession *s = [CDRDevModeSession sessionFromArguments:@[@"conductor", @"--dev-mode", @"com.ranvel.muwav"] error:NULL];
    XCTAssertNotNil(s);
    XCTAssertTrue(s.devModeEnabled);
    XCTAssertEqualObjects(s.devModeBundleID, @"com.ranvel.muwav");
}

- (void)testRepeatedFlagIsAnError {
    NSError *error = nil;
    CDRDevModeSession *s = [CDRDevModeSession sessionFromArguments:@[@"conductor", @"--dev-mode", @"com.a.a", @"--dev-mode", @"com.b.b"] error:&error];
    XCTAssertNil(s);
    XCTAssertNotNil(error);
}

- (void)testMissingOperandIsAnError {
    NSError *error = nil;
    CDRDevModeSession *s = [CDRDevModeSession sessionFromArguments:@[@"conductor", @"--dev-mode"] error:&error];
    XCTAssertNil(s);
    XCTAssertNotNil(error);
}

- (void)testFlagFollowedByAnotherFlagIsAnError {
    NSError *error = nil;
    CDRDevModeSession *s = [CDRDevModeSession sessionFromArguments:@[@"conductor", @"--dev-mode", @"-NSSomething"] error:&error];
    XCTAssertNil(s);
    XCTAssertNotNil(error);
}

- (void)testVisibilityFiltering {
    CDRDevModeSession *dev = [CDRDevModeSession sessionFromArguments:@[@"conductor", @"--dev-mode", @"com.a.a"] error:NULL];
    XCTAssertTrue([dev isBundleVisible:@"com.a.a"]);
    XCTAssertFalse([dev isBundleVisible:@"com.b.b"]);

    CDRDevModeSession *normal = [CDRDevModeSession sessionFromArguments:@[@"conductor"] error:NULL];
    XCTAssertTrue([normal isBundleVisible:@"com.a.a"]);
    XCTAssertTrue([normal isBundleVisible:@"com.b.b"]);
}

- (void)testTransportPolicy {
    NSURL *https = [NSURL URLWithString:@"https://example.com/m.json"];
    NSURL *http = [NSURL URLWithString:@"http://localhost:8000/m.json"];
    NSURL *file = [NSURL URLWithString:@"file:///etc/passwd"];

    CDRDevModeSession *normal = [CDRDevModeSession sessionFromArguments:@[@"conductor"] error:NULL];
    XCTAssertTrue([normal allowsURL:https forBundleID:@"com.a.a"]);
    XCTAssertFalse([normal allowsURL:http forBundleID:@"com.a.a"]);
    XCTAssertFalse([normal allowsURL:file forBundleID:@"com.a.a"]);

    CDRDevModeSession *dev = [CDRDevModeSession sessionFromArguments:@[@"conductor", @"--dev-mode", @"com.a.a"] error:NULL];
    XCTAssertTrue([dev allowsURL:https forBundleID:@"com.a.a"]);
    XCTAssertTrue([dev allowsURL:http forBundleID:@"com.a.a"]);
    // HTTP is per-bundle even in dev mode.
    XCTAssertFalse([dev allowsURL:http forBundleID:@"com.b.b"]);
    // Non-HTTP(S) schemes are never allowed.
    XCTAssertFalse([dev allowsURL:file forBundleID:@"com.a.a"]);
}

@end
