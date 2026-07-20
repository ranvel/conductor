//
//  CDRAppRegistrationTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRAppRegistration.h"
#import "CDRErrors.h"

@interface CDRAppRegistrationTests : XCTestCase
@property (nonatomic) NSURL *tempDir;
@end

@implementation CDRAppRegistrationTests

- (void)setUp {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"CDRAppRegistrationTests-%@", NSUUID.UUID.UUIDString]];
    self.tempDir = [NSURL fileURLWithPath:path isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDir withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDir error:NULL];
}

/// Builds a minimal .app bundle skeleton with the given Info.plist keys and
/// optional conductor.json dictionary. Returns the bundle URL.
- (NSURL *)makeAppBundleNamed:(NSString *)name
                    infoPlist:(NSDictionary *)info
                conductorJSON:(nullable NSDictionary *)conductorJSON {
    NSURL *appURL = [self.tempDir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"app"]];
    NSURL *resources = [appURL URLByAppendingPathComponent:@"Contents/Resources"];
    [[NSFileManager defaultManager] createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:NULL];

    NSURL *plistURL = [appURL URLByAppendingPathComponent:@"Contents/Info.plist"];
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    [plistData writeToURL:plistURL atomically:YES];

    if (conductorJSON) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:conductorJSON options:0 error:NULL];
        [jsonData writeToURL:[appURL URLByAppendingPathComponent:[CDRAppRegistration conductorJSONRelativePath]] atomically:YES];
    }
    return appURL;
}

static NSDictionary *ValidInfoPlist(void) {
    return @{
        @"CFBundleIdentifier": @"com.example.testee",
        @"CFBundleShortVersionString": @"1.0",
        @"CFBundleVersion": @"100",
        @"CFBundlePackageType": @"APPL",
    };
}

static NSDictionary *ValidConductorJSON(void) {
    return @{
        @"conductor": @1,
        @"update_url": @"https://example.com/manifest.json",
        @"fallback_url": @"https://cdn.example.com/manifest.json",
        @"vendor_url": @"https://example.com",
    };
}

- (void)testValidRegistration {
    NSURL *appURL = [self makeAppBundleNamed:@"Valid" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNotNil(reg);
    XCTAssertNil(error);
    XCTAssertEqualObjects(reg.bundleID, @"com.example.testee");
    XCTAssertEqualObjects(reg.installedShortVersion, @"1.0");
    XCTAssertEqualObjects(reg.installedBuildVersion, @"100");
    XCTAssertEqualObjects(reg.updateURL.absoluteString, @"https://example.com/manifest.json");
    XCTAssertEqualObjects(reg.fallbackURL.host, @"cdn.example.com");
    XCTAssertEqualObjects(reg.vendorURL.absoluteString, @"https://example.com");
}

- (void)testOptionalURLsMayBeAbsent {
    NSDictionary *json = @{ @"conductor": @1, @"update_url": @"https://example.com/m.json" };
    NSURL *appURL = [self makeAppBundleNamed:@"NoOptionals" infoPlist:ValidInfoPlist() conductorJSON:json];
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    XCTAssertNotNil(reg);
    XCTAssertNil(reg.fallbackURL);
    XCTAssertNil(reg.vendorURL);
}

- (void)testMissingConductorJSONFails {
    NSURL *appURL = [self makeAppBundleNamed:@"NoJSON" infoPlist:ValidInfoPlist() conductorJSON:nil];
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNil(reg);
    XCTAssertEqual(error.code, CDRErrorConductorJSONMalformed);
}

- (void)testUnsupportedFormatVersionFails {
    NSMutableDictionary *json = [ValidConductorJSON() mutableCopy];
    json[@"conductor"] = @99;
    NSURL *appURL = [self makeAppBundleNamed:@"BadFormat" infoPlist:ValidInfoPlist() conductorJSON:json];
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNil(reg);
    XCTAssertEqual(error.code, CDRErrorUnsupportedFormatVersion);
}

- (void)testMissingUpdateURLFails {
    NSDictionary *json = @{ @"conductor": @1 };
    NSURL *appURL = [self makeAppBundleNamed:@"NoUpdateURL" infoPlist:ValidInfoPlist() conductorJSON:json];
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNil(reg);
    XCTAssertEqual(error.code, CDRErrorConductorJSONMalformed);
}

- (void)testRelativeUpdateURLFails {
    NSMutableDictionary *json = [ValidConductorJSON() mutableCopy];
    json[@"update_url"] = @"manifest.json";
    NSURL *appURL = [self makeAppBundleNamed:@"RelativeURL" infoPlist:ValidInfoPlist() conductorJSON:json];
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNil(reg);
    XCTAssertEqual(error.code, CDRErrorConductorJSONMalformed);
}

- (void)testMissingShortVersionFails {
    NSDictionary *info = @{ @"CFBundleIdentifier": @"com.example.noversion" };
    NSURL *appURL = [self makeAppBundleNamed:@"NoVersion" infoPlist:info conductorJSON:ValidConductorJSON()];
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNil(reg);
    XCTAssertNotNil(error);
}

@end
