//
//  CDRVersionTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRVersion.h"

@interface CDRVersionTests : XCTestCase
@end

@implementation CDRVersionTests

- (void)testNumericComponentComparison {
    XCTAssertEqual([CDRVersion compare:@"1.9" to:@"1.10"], NSOrderedAscending);
    XCTAssertEqual([CDRVersion compare:@"1.10" to:@"1.9"], NSOrderedDescending);
    XCTAssertEqual([CDRVersion compare:@"2.0" to:@"10.0"], NSOrderedAscending);
}

- (void)testMissingComponentsCompareAsZero {
    XCTAssertEqual([CDRVersion compare:@"1.2" to:@"1.2.0"], NSOrderedSame);
    XCTAssertEqual([CDRVersion compare:@"1.2" to:@"1.2.1"], NSOrderedAscending);
}

- (void)testEquality {
    XCTAssertEqual([CDRVersion compare:@"3.4.5" to:@"3.4.5"], NSOrderedSame);
}

- (void)testNonNumericComponentsCompareLexically {
    XCTAssertEqual([CDRVersion compare:@"1.0b" to:@"1.0b"], NSOrderedSame);
    XCTAssertEqual([CDRVersion compare:@"1.a" to:@"1.b"], NSOrderedAscending);
}

- (void)testNewerThanShortVersionWins {
    XCTAssertTrue([CDRVersion isVersion:@"1.1" build:@"110" newerThan:@"1.0" build:@"100"]);
    XCTAssertFalse([CDRVersion isVersion:@"1.0" build:@"200" newerThan:@"1.1" build:@"100"]);
}

- (void)testNewerThanBuildTiebreak {
    XCTAssertTrue([CDRVersion isVersion:@"1.0" build:@"101" newerThan:@"1.0" build:@"100"]);
    XCTAssertFalse([CDRVersion isVersion:@"1.0" build:@"100" newerThan:@"1.0" build:@"100"]);
    XCTAssertFalse([CDRVersion isVersion:@"1.0" build:@"99" newerThan:@"1.0" build:@"100"]);
}

- (void)testEqualVersionsWithoutBuildsAreNotNewer {
    XCTAssertFalse([CDRVersion isVersion:@"1.0" build:nil newerThan:@"1.0" build:nil]);
    XCTAssertFalse([CDRVersion isVersion:@"1.0" build:@"5" newerThan:@"1.0" build:nil]);
}

#pragma mark - Major versions (CND-5)

- (void)testMajorComponent {
    XCTAssertEqualObjects([CDRVersion majorComponentOf:@"2.0.1"], @2);
    XCTAssertEqualObjects([CDRVersion majorComponentOf:@"0.9"], @0);
    XCTAssertEqualObjects([CDRVersion majorComponentOf:@"3"], @3);
    XCTAssertEqualObjects([CDRVersion majorComponentOf:@"10.4"], @10);
    for (NSString *bad in @[@"beta.3", @"v2.0", @"2b.1", @"", @".5", @"-1.0", @" 2.0"]) {
        XCTAssertNil([CDRVersion majorComponentOf:bad], @"%@ has no numeric leading component", bad);
    }
}

- (void)testMajorUpgradeMeansTheLeadingComponentGrew {
    // "Major" is the leading component changing, not "reaching 1.0".
    XCTAssertTrue([CDRVersion isMajorUpgradeFrom:@"0.9" to:@"1.0"]);
    XCTAssertTrue([CDRVersion isMajorUpgradeFrom:@"2.0.1" to:@"3"]);
    XCTAssertTrue([CDRVersion isMajorUpgradeFrom:@"1.9.9" to:@"10.0"]);

    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"1.9" to:@"1.10"]);
    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"1.2" to:@"1.4"]);
    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"2.0" to:@"2.0"]);
    // Going down is never a major *upgrade* (and is refused elsewhere anyway).
    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"3.0" to:@"2.9"]);
}

- (void)testNonNumericLeadingComponentsAreNeverMajor {
    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"beta.1" to:@"2.0"]);
    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"1.0" to:@"next.0"]);
    XCTAssertFalse([CDRVersion isMajorUpgradeFrom:@"a.1" to:@"b.1"]);
}

@end
