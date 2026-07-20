//
//  CDRUpdateStateStoreTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRUpdateStateStore.h"

@interface CDRUpdateStateStoreTests : XCTestCase
@property (nonatomic) NSURL *storeDir;
@property (nonatomic) NSDate *now;
@end

@implementation CDRUpdateStateStoreTests

static NSString * const kBundleID = @"com.example.app";

- (void)setUp {
    [super setUp];
    self.storeDir = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-store-tests-%@", NSUUID.UUID.UUIDString]
                        isDirectory:YES];
    self.now = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.storeDir error:NULL];
    [super tearDown];
}

- (CDRUpdateStateStore *)freshStore {
    return [[CDRUpdateStateStore alloc] initWithDirectoryURL:self.storeDir now:self.now];
}

- (NSURL *)storeFileURL {
    return [self.storeDir URLByAppendingPathComponent:@"UpdateState.plist"];
}

#pragma mark - Round-trip

- (void)testRoundTripAcrossStoreInstances {
    CDRUpdateStateStore *store = [self freshStore];
    CDRAppUpdateState *state = [[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:@"110" at:self.now];
    state = [state stateByNotingNotifiedVersion:@"1.1" build:@"110" at:self.now];
    [store putState:state];

    CDRAppUpdateState *reloaded = [[self freshStore] stateForBundleID:kBundleID];
    XCTAssertNotNil(reloaded);
    XCTAssertEqualObjects(reloaded.lastSeenVersion, @"1.1");
    XCTAssertEqualObjects(reloaded.lastSeenBuild, @"110");
    XCTAssertEqualObjects(reloaded.firstSeenByVersion[@"1.1"], self.now);
    XCTAssertEqualObjects(reloaded.lastNotifiedVersion, @"1.1");
    XCTAssertEqualObjects(reloaded.lastNotifiedBuild, @"110");
    XCTAssertEqualObjects(reloaded.notifiedAt, self.now);
    XCTAssertEqualObjects(reloaded.updatedAt, self.now);
}

- (void)testMissingFileYieldsEmptyStore {
    XCTAssertNil([[self freshStore] stateForBundleID:kBundleID]);
}

- (void)testCorruptFileYieldsEmptyStore {
    [[NSFileManager defaultManager] createDirectoryAtURL:self.storeDir
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[self storeFileURL] atomically:YES];
    XCTAssertNil([[self freshStore] stateForBundleID:kBundleID]);
}

- (void)testNonDictionaryRootYieldsEmptyStore {
    [[NSFileManager defaultManager] createDirectoryAtURL:self.storeDir
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@[@"array root"]
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0 error:NULL];
    [data writeToURL:[self storeFileURL] atomically:YES];
    XCTAssertNil([[self freshStore] stateForBundleID:kBundleID]);
}

- (void)testUnknownFormatVersionStartsFresh {
    CDRUpdateStateStore *store = [self freshStore];
    [store putState:[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now]];

    // Rewrite the file claiming a future format; the record must not be misread.
    NSMutableDictionary *root = [[NSPropertyListSerialization
        propertyListWithData:[NSData dataWithContentsOfURL:[self storeFileURL]]
                     options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    root[@"format_version"] = @99;
    [[NSPropertyListSerialization dataWithPropertyList:root
                                                format:NSPropertyListXMLFormat_v1_0
                                               options:0 error:NULL] writeToURL:[self storeFileURL] atomically:YES];

    XCTAssertNil([[self freshStore] stateForBundleID:kBundleID]);
}

- (void)testGarbageEntryIsSkippedOthersSurvive {
    CDRUpdateStateStore *store = [self freshStore];
    [store putState:[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now]];

    NSMutableDictionary *root = [[NSPropertyListSerialization
        propertyListWithData:[NSData dataWithContentsOfURL:[self storeFileURL]]
                     options:NSPropertyListMutableContainers format:NULL error:NULL] mutableCopy];
    root[@"apps"][@"com.example.garbage"] = @"not a dictionary";
    [[NSPropertyListSerialization dataWithPropertyList:root
                                                format:NSPropertyListXMLFormat_v1_0
                                               options:0 error:NULL] writeToURL:[self storeFileURL] atomically:YES];

    CDRUpdateStateStore *reloaded = [self freshStore];
    XCTAssertNotNil([reloaded stateForBundleID:kBundleID]);
    XCTAssertNil([reloaded stateForBundleID:@"com.example.garbage"]);
}

#pragma mark - State semantics

- (void)testFirstSeenIsSetOncePerVersion {
    NSDate *later = [self.now dateByAddingTimeInterval:3600];
    CDRAppUpdateState *state = [[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now];
    state = [state stateBySeeingVersion:@"1.1" build:nil at:later];
    // Re-observing must not restart the soak clock.
    XCTAssertEqualObjects(state.firstSeenByVersion[@"1.1"], self.now);
    XCTAssertEqualObjects(state.updatedAt, later);
}

- (void)testFirstSeenPrunedToSeenAndNotified {
    NSDate *t1 = self.now, *t2 = [self.now dateByAddingTimeInterval:100], *t3 = [self.now dateByAddingTimeInterval:200];
    CDRAppUpdateState *state = [[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:t1]
        stateBySeeingVersion:@"1.1" build:nil at:t1];
    state = [state stateByNotingNotifiedVersion:@"1.1" build:nil at:t1];
    state = [state stateBySeeingVersion:@"1.2" build:nil at:t2];   // 1.1 kept: still notified
    XCTAssertNotNil(state.firstSeenByVersion[@"1.1"]);
    XCTAssertNotNil(state.firstSeenByVersion[@"1.2"]);

    state = [state stateBySeeingVersion:@"1.3" build:nil at:t3];   // 1.2 superseded, never notified → dropped
    XCTAssertEqual(state.firstSeenByVersion.count, 2u);
    XCTAssertNotNil(state.firstSeenByVersion[@"1.1"]);
    XCTAssertNil(state.firstSeenByVersion[@"1.2"]);
    XCTAssertEqualObjects(state.firstSeenByVersion[@"1.3"], t3);
}

- (void)testClearNotifiedRemovesAllNotifiedFields {
    CDRUpdateStateStore *store = [self freshStore];
    [store noteNotifiedVersion:@"1.1" build:@"110" forBundleID:kBundleID at:self.now];
    [store clearNotifiedVersionForBundleID:kBundleID at:[self.now dateByAddingTimeInterval:60]];

    CDRAppUpdateState *state = [[self freshStore] stateForBundleID:kBundleID];
    XCTAssertNotNil(state);
    XCTAssertNil(state.lastNotifiedVersion);
    XCTAssertNil(state.lastNotifiedBuild);
    XCTAssertNil(state.notifiedAt);
}

- (void)testClearNotifiedForUnknownBundleIDIsNoOp {
    CDRUpdateStateStore *store = [self freshStore];
    [store clearNotifiedVersionForBundleID:@"com.example.stranger" at:self.now];
    XCTAssertNil([store stateForBundleID:@"com.example.stranger"]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[self storeFileURL].path]);
}

- (void)testNoteNotifiedCreatesRecordForUnknownApp {
    CDRUpdateStateStore *store = [self freshStore];
    [store noteNotifiedVersion:@"2.0" build:nil forBundleID:kBundleID at:self.now];
    CDRAppUpdateState *state = [[self freshStore] stateForBundleID:kBundleID];
    XCTAssertEqualObjects(state.lastNotifiedVersion, @"2.0");
}

#pragma mark - Retention (M2 decision: 90 days on updated_at, swept at load)

- (void)testRecordUntouchedFor91DaysIsDroppedAtLoad {
    NSDate *ancient = [self.now dateByAddingTimeInterval:-91.0 * 24 * 3600];
    CDRUpdateStateStore *store = [[CDRUpdateStateStore alloc] initWithDirectoryURL:self.storeDir now:ancient];
    [store putState:[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:ancient]
        stateBySeeingVersion:@"1.1" build:nil at:ancient]];

    XCTAssertNil([[self freshStore] stateForBundleID:kBundleID]);
}

- (void)testRecordUntouchedFor89DaysSurvivesLoad {
    NSDate *recent = [self.now dateByAddingTimeInterval:-89.0 * 24 * 3600];
    CDRUpdateStateStore *store = [[CDRUpdateStateStore alloc] initWithDirectoryURL:self.storeDir now:recent];
    [store putState:[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:recent]
        stateBySeeingVersion:@"1.1" build:nil at:recent]];

    XCTAssertNotNil([[self freshStore] stateForBundleID:kBundleID]);
}

@end
