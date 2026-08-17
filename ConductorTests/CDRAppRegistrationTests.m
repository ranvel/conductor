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

#pragma mark - Fresh version reads (NSBundle caches per path; registration must not)

/// The bug behind a stale "Installed" column: NSBundle caches the info
/// dictionary per path for the process lifetime, so re-registering after an
/// in-place swap must NOT go through NSBundle.
- (void)testReRegistrationReadsFreshVersionAfterPlistRewrite {
    NSURL *appURL = [self makeAppBundleNamed:@"Fresh" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    CDRAppRegistration *before = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    XCTAssertEqualObjects(before.installedShortVersion, @"1.0");

    NSMutableDictionary *info = [ValidInfoPlist() mutableCopy];
    info[@"CFBundleShortVersionString"] = @"1.1";
    info[@"CFBundleVersion"] = @"101";
    [self makeAppBundleNamed:@"Fresh" infoPlist:info conductorJSON:ValidConductorJSON()];

    CDRAppRegistration *after = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    XCTAssertEqualObjects(after.installedShortVersion, @"1.1");
    XCTAssertEqualObjects(after.installedBuildVersion, @"101");
}

- (void)testRefreshingInstalledVersionPicksUpPlistChange {
    NSURL *appURL = [self makeAppBundleNamed:@"Refresh" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];

    NSMutableDictionary *info = [ValidInfoPlist() mutableCopy];
    info[@"CFBundleShortVersionString"] = @"2.0";
    info[@"CFBundleVersion"] = @"200";
    [self makeAppBundleNamed:@"Refresh" infoPlist:info conductorJSON:ValidConductorJSON()];

    CDRAppRegistration *fresh = [reg registrationByRefreshingInstalledVersion];
    XCTAssertNotEqual(fresh, reg);
    XCTAssertEqualObjects(fresh.installedShortVersion, @"2.0");
    XCTAssertEqualObjects(fresh.installedBuildVersion, @"200");
    XCTAssertEqualObjects(fresh.bundleID, reg.bundleID);
    XCTAssertEqualObjects(fresh.appURL, reg.appURL);
    XCTAssertEqualObjects(fresh.updateURL, reg.updateURL);
    XCTAssertEqualObjects(fresh.fallbackURL, reg.fallbackURL);
    XCTAssertEqualObjects(fresh.vendorURL, reg.vendorURL);
}

- (void)testRefreshingReturnsSelfWhenUnchanged {
    NSURL *appURL = [self makeAppBundleNamed:@"Same" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    XCTAssertEqual([reg registrationByRefreshingInstalledVersion], reg);
}

- (void)testRefreshingReturnsSelfWhenPlistMissing {
    NSURL *appURL = [self makeAppBundleNamed:@"Gone" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    [[NSFileManager defaultManager] removeItemAtURL:appURL error:NULL];
    XCTAssertEqual([reg registrationByRefreshingInstalledVersion], reg);
}

- (void)testRefreshingReturnsSelfWhenBundleIDChanged {
    NSURL *appURL = [self makeAppBundleNamed:@"Swapped" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];

    NSMutableDictionary *info = [ValidInfoPlist() mutableCopy];
    info[@"CFBundleIdentifier"] = @"com.example.other";
    info[@"CFBundleShortVersionString"] = @"9.9";
    [self makeAppBundleNamed:@"Swapped" infoPlist:info conductorJSON:ValidConductorJSON()];

    XCTAssertEqual([reg registrationByRefreshingInstalledVersion], reg);
}

- (void)testRegistrationWithInstalledVersionCopies {
    NSURL *appURL = [self makeAppBundleNamed:@"Copied" infoPlist:ValidInfoPlist() conductorJSON:ValidConductorJSON()];
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    CDRAppRegistration *pushed = [reg registrationWithInstalledShortVersion:@"3.0" buildVersion:nil];
    XCTAssertEqualObjects(pushed.installedShortVersion, @"3.0");
    XCTAssertNil(pushed.installedBuildVersion);
    XCTAssertEqualObjects(pushed.bundleID, reg.bundleID);
    XCTAssertEqualObjects(pushed.appURL, reg.appURL);
    XCTAssertEqualObjects(pushed.updateURL, reg.updateURL);
    XCTAssertEqualObjects(pushed.fallbackURL, reg.fallbackURL);
    XCTAssertEqualObjects(pushed.vendorURL, reg.vendorURL);
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
