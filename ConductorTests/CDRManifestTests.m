//
//  CDRManifestTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRManifest.h"
#import "CDRErrors.h"

@interface CDRManifestTests : XCTestCase
@end

@implementation CDRManifestTests

static NSData *JSONData(NSDictionary *dict) {
    return [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
}

static NSDictionary *ValidManifestDict(void) {
    return @{
        @"conductor_manifest": @1,
        @"bundle_id": @"com.example.app",
        @"version": @"1.1",
        @"url": @"https://example.com/app-1.1.dmg",
    };
}

- (void)testValidMinimalManifest {
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(ValidManifestDict()) error:&error];
    XCTAssertNotNil(m);
    XCTAssertNil(error);
    XCTAssertEqualObjects(m.bundleID, @"com.example.app");
    XCTAssertEqualObjects(m.version, @"1.1");
    XCTAssertEqualObjects(m.artifactURL.absoluteString, @"https://example.com/app-1.1.dmg");
    XCTAssertNil(m.build);
    XCTAssertNil(m.sha256);
    XCTAssertEqual(m.urgency, CDRUrgencyNone);
}

- (void)testOptionalFields {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"build"] = @"110";
    dict[@"sha256"] = @"ABCDEF";
    dict[@"changelog_url"] = @"https://example.com/changelog";
    dict[@"min_system_version"] = @"13.0";
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
    XCTAssertNotNil(m);
    XCTAssertEqualObjects(m.build, @"110");
    XCTAssertEqualObjects(m.sha256, @"abcdef"); // normalized to lowercase
    XCTAssertEqualObjects(m.changelogURL.host, @"example.com");
    XCTAssertEqualObjects(m.minSystemVersion, @"13.0");
}

- (void)testMissingRequiredFieldFails {
    for (NSString *key in @[@"conductor_manifest", @"bundle_id", @"version", @"url"]) {
        NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
        [dict removeObjectForKey:key];
        NSError *error = nil;
        CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
        XCTAssertNil(m, @"expected failure with %@ missing", key);
        XCTAssertEqualObjects(error.domain, CDRErrorDomain);
    }
}

- (void)testUnsupportedFormatVersionFails {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"conductor_manifest"] = @2;
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
    XCTAssertNil(m);
    XCTAssertEqual(error.code, CDRErrorUnsupportedFormatVersion);
}

- (void)testUrgencyTokens {
    NSDictionary<NSString *, NSNumber *> *cases = @{
        @"system_risk": @(CDRUrgencySystemRisk),
        @"data_loss": @(CDRUrgencyDataLoss),
        @"data_exfiltration": @(CDRUrgencyDataExfiltration),
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *token, NSNumber *expected, BOOL *stop) {
        NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
        dict[@"urgency"] = token;
        CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:NULL];
        XCTAssertEqual(m.urgency, (CDRUrgency)expected.integerValue);
    }];
}

- (void)testUnknownUrgencyTokenIsIgnored {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"urgency"] = @"mildly_exciting_new_features";
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:NULL];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.urgency, CDRUrgencyNone);
}

- (void)testGarbageDataFails {
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNil(m);
    XCTAssertEqual(error.code, CDRErrorManifestMalformed);
}

- (void)testRelativeArtifactURLFails {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"url"] = @"downloads/app.dmg";
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
    XCTAssertNil(m);
    XCTAssertEqual(error.code, CDRErrorManifestMalformed);
}

@end
