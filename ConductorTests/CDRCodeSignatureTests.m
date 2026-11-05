//
//  CDRCodeSignatureTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRCodeSignature.h"
#import "CDRBundleInspector.h"
#import "CDRErrors.h"

/// These run against the test HOST bundle (Conductor.app itself) — a real,
/// locally signed bundle carrying the development team, which satisfies
/// `anchor apple generic` just like a Developer ID signature does.
@interface CDRCodeSignatureTests : XCTestCase
@property (nonatomic) NSURL *hostBundleURL;
@end

@implementation CDRCodeSignatureTests

- (void)setUp {
    self.hostBundleURL = [NSBundle mainBundle].bundleURL;
    XCTAssertEqualObjects(self.hostBundleURL.pathExtension, @"app",
        @"tests must run hosted in the Conductor app");
}

- (void)testTeamIdentifierOfHostBundle {
    NSError *error = nil;
    NSString *team = [CDRCodeSignature teamIdentifierForBundleAtURL:self.hostBundleURL error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(team, @"F252L9GUBW");
}

- (void)testValidationPassesWithCorrectPinnedTeam {
    NSError *error = nil;
    BOOL ok = [CDRCodeSignature validateBundleAtURL:self.hostBundleURL
                                       pinnedTeamID:@"F252L9GUBW"
                                              error:&error];
    XCTAssertTrue(ok, @"%@", error);
}

- (void)testValidationFailsWithWrongPinnedTeam {
    NSError *error = nil;
    BOOL ok = [CDRCodeSignature validateBundleAtURL:self.hostBundleURL
                                       pinnedTeamID:@"XXXXXXXXXX"
                                              error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, CDRErrorTeamIDMismatch);
}

- (void)testUnsignedBundleIsDetected {
    // A bare directory posing as a bundle has no signature at all.
    NSURL *dir = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"Unsigned-%@.app", NSUUID.UUID.UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:[dir URLByAppendingPathComponent:@"Contents/MacOS"]
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    NSString *team = [CDRCodeSignature teamIdentifierForBundleAtURL:dir error:&error];
    XCTAssertNil(team);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, CDRErrorDomain);
    [[NSFileManager defaultManager] removeItemAtURL:dir error:NULL];
}

- (void)testAdHocSignedBinaryHasNoTeam {
    // Copy a small system binary and ad-hoc sign it; expect InstalledAdHoc.
    NSURL *tmp = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"adhoc-%@", NSUUID.UUID.UUIDString]]];
    NSError *copyError = nil;
    [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:@"/bin/echo"]
                                            toURL:tmp error:&copyError];
    XCTAssertNil(copyError);

    NSTask *codesign = [[NSTask alloc] init];
    codesign.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
    codesign.arguments = @[@"--force", @"--sign", @"-", tmp.path];
    [codesign launchAndReturnError:NULL];
    [codesign waitUntilExit];
    XCTAssertEqual(codesign.terminationStatus, 0);

    NSError *error = nil;
    NSString *team = [CDRCodeSignature teamIdentifierForBundleAtURL:tmp error:&error];
    XCTAssertNil(team);
    XCTAssertEqual(error.code, CDRErrorInstalledAdHoc);
    [[NSFileManager defaultManager] removeItemAtURL:tmp error:NULL];
}

#pragma mark - CDRBundleInspector (display only)

- (void)testDeveloperNameOfHostBundleIsTheSigningOrganization {
    NSString *name = [CDRBundleInspector developerNameForBundleAtURL:[self hostBundleURL]];
    XCTAssertGreaterThan(name.length, 0u);
    // The organization alone — not the certificate's whole common name.
    XCTAssertFalse([name containsString:@"Developer ID"]);
    XCTAssertFalse([name containsString:@"F252L9GUBW"]);
}

- (void)testDeveloperNameIsNilForAnAdHocSignedBinary {
    NSURL *copy = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-inspector-%@", NSUUID.UUID.UUIDString]];
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:@"/bin/echo"]
                                                          toURL:copy error:NULL]);
    NSTask *sign = [[NSTask alloc] init];
    sign.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
    sign.arguments = @[@"--force", @"--sign", @"-", copy.path];
    sign.standardError = [NSPipe pipe];
    [sign launchAndReturnError:NULL];
    [sign waitUntilExit];
    XCTAssertNil([CDRBundleInspector developerNameForBundleAtURL:copy]);
    XCTAssertNil([CDRBundleInspector developerNameForBundleAtURL:[NSURL fileURLWithPath:@"/nonexistent.app"]]);
    [[NSFileManager defaultManager] removeItemAtURL:copy error:NULL];
}

@end
