//
//  CDRIgnoreListTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRIgnoreList.h"

@interface CDRIgnoreListTests : XCTestCase
@property (nonatomic) NSString *suiteName;
@property (nonatomic) NSUserDefaults *defaults;
@end

@implementation CDRIgnoreListTests

- (void)setUp {
    [super setUp];
    self.suiteName = [NSString stringWithFormat:@"cdr-ignore-tests-%@", NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:self.suiteName];
    [super tearDown];
}

- (void)testEmptyByDefault {
    XCTAssertEqual(CDRIgnoredBundleIDs(self.defaults).count, 0u);
}

- (void)testSetAndUnsetRoundTrip {
    CDRSetBundleIDIgnored(@"com.example.a", YES, self.defaults);
    CDRSetBundleIDIgnored(@"com.example.b", YES, self.defaults);
    NSSet *ignored = CDRIgnoredBundleIDs(self.defaults);
    XCTAssertTrue([ignored containsObject:@"com.example.a"]);
    XCTAssertTrue([ignored containsObject:@"com.example.b"]);

    CDRSetBundleIDIgnored(@"com.example.a", NO, self.defaults);
    ignored = CDRIgnoredBundleIDs(self.defaults);
    XCTAssertFalse([ignored containsObject:@"com.example.a"]);
    XCTAssertTrue([ignored containsObject:@"com.example.b"]);
}

- (void)testSetIsIdempotent {
    CDRSetBundleIDIgnored(@"com.example.a", YES, self.defaults);
    CDRSetBundleIDIgnored(@"com.example.a", YES, self.defaults);
    XCTAssertEqual(CDRIgnoredBundleIDs(self.defaults).count, 1u);
    CDRSetBundleIDIgnored(@"com.example.a", NO, self.defaults);
    CDRSetBundleIDIgnored(@"com.example.a", NO, self.defaults);
    XCTAssertEqual(CDRIgnoredBundleIDs(self.defaults).count, 0u);
}

- (void)testGarbageValueReadsAsEmpty {
    [self.defaults setObject:@"not-an-array" forKey:CDRIgnoredBundleIDsDefaultsKey];
    XCTAssertEqual(CDRIgnoredBundleIDs(self.defaults).count, 0u);

    [self.defaults setObject:@[@42, @"com.example.a"] forKey:CDRIgnoredBundleIDsDefaultsKey];
    NSSet *ignored = CDRIgnoredBundleIDs(self.defaults);
    XCTAssertEqualObjects(ignored, [NSSet setWithObject:@"com.example.a"]);
}

@end
