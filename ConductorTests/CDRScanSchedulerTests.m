//
//  CDRScanSchedulerTests.m
//  ConductorTests
//
//  Token round-trips and the pure trigger-coalescing decision — injected
//  dates and a throwaway defaults suite, no real timers.
//

#import <XCTest/XCTest.h>
#import "CDRScanScheduler.h"

static const NSTimeInterval kMinute = 60.0;
static const NSTimeInterval kHour = 60.0 * kMinute;

@interface CDRScanSchedulerTests : XCTestCase
@property (nonatomic) NSString *suiteName;
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic) CDRScanScheduler *scheduler;
@property (nonatomic) NSDate *epoch;
@end

@implementation CDRScanSchedulerTests

- (void)setUp {
    [super setUp];
    self.suiteName = [NSString stringWithFormat:@"cdr-scheduler-tests-%@", NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
    self.scheduler = [[CDRScanScheduler alloc] initWithDefaults:self.defaults
                                                        handler:^(CDRScanTrigger trigger) {}];
    self.epoch = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:self.suiteName];
    [super tearDown];
}

- (NSDate *)after:(NSTimeInterval)interval {
    return [self.epoch dateByAddingTimeInterval:interval];
}

#pragma mark - Tokens

- (void)testTokenRoundTrips {
    CDRScanCadence all[] = {CDRScanCadenceManual, CDRScanCadenceSixHours,
                            CDRScanCadenceDaily, CDRScanCadenceWeekly};
    for (size_t i = 0; i < 4; i++) {
        XCTAssertEqual(CDRScanCadenceFromDefaultsToken(CDRScanCadenceDefaultsToken(all[i])), all[i]);
    }
}

- (void)testGarbageTokenFallsBackToDaily {
    XCTAssertEqual(CDRScanCadenceFromDefaultsToken(nil), CDRScanCadenceDaily);
    XCTAssertEqual(CDRScanCadenceFromDefaultsToken(@"soon"), CDRScanCadenceDaily);
    XCTAssertEqual(CDRScanCadenceFromDefaultsToken(@""), CDRScanCadenceDaily);
}

- (void)testIntervals {
    XCTAssertEqual(CDRScanCadenceInterval(CDRScanCadenceManual), 0);
    XCTAssertEqual(CDRScanCadenceInterval(CDRScanCadenceSixHours), 6 * kHour);
    XCTAssertEqual(CDRScanCadenceInterval(CDRScanCadenceDaily), 24 * kHour);
    XCTAssertEqual(CDRScanCadenceInterval(CDRScanCadenceWeekly), 7 * 24 * kHour);
}

#pragma mark - Decision matrix

- (void)testManualCadenceNeverScans {
    self.scheduler.cadence = CDRScanCadenceManual;
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerTimer now:self.epoch]);
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerWake now:self.epoch]);
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerNetworkChange now:self.epoch]);
}

- (void)testFirstEverScanFiresOnAnyTrigger {
    self.scheduler.cadence = CDRScanCadenceDaily;
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerTimer now:self.epoch]);
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerWake now:self.epoch]);
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerNetworkChange now:self.epoch]);
}

- (void)testMinimumSpacingSuppressesEveryTrigger {
    self.scheduler.cadence = CDRScanCadenceSixHours;
    [self.scheduler noteScanCompletedAt:self.epoch];
    NSDate *fiveMinutesLater = [self after:5 * kMinute];
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerTimer now:fiveMinutesLater]);
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerWake now:fiveMinutesLater]);
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerNetworkChange now:fiveMinutesLater]);
}

- (void)testWakeAndNetworkOnlyCatchUpOverdueScans {
    self.scheduler.cadence = CDRScanCadenceSixHours;
    [self.scheduler noteScanCompletedAt:self.epoch];

    // Past the spacing floor but well inside the cadence interval: wake and
    // network stay quiet (they add no extra scans)…
    NSDate *oneHourLater = [self after:1 * kHour];
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerWake now:oneHourLater]);
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerNetworkChange now:oneHourLater]);
    // …but the timer may (it *is* the cadence; tolerance can land it early).
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerTimer now:oneHourLater]);

    // Overdue (the Mac slept through the tick): wake/network catch it up.
    NSDate *sevenHoursLater = [self after:7 * kHour];
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerWake now:sevenHoursLater]);
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerNetworkChange now:sevenHoursLater]);
}

- (void)testNoteScanCompletedPersists {
    [self.scheduler noteScanCompletedAt:self.epoch];
    XCTAssertEqualObjects(self.scheduler.lastScanDate, self.epoch);

    // A fresh scheduler over the same defaults sees it (relaunch survives).
    CDRScanScheduler *fresh = [[CDRScanScheduler alloc] initWithDefaults:self.defaults
                                                                 handler:^(CDRScanTrigger t) {}];
    XCTAssertEqualObjects(fresh.lastScanDate, self.epoch);
}

- (void)testDebugOverrideShrinksIntervalAndSpacing {
    self.scheduler.cadence = CDRScanCadenceDaily;
    [self.defaults setDouble:60 forKey:CDRScanIntervalOverrideDefaultsKey];
    [self.scheduler noteScanCompletedAt:self.epoch];

    // 45s: past the shrunk spacing floor (30s), timer fires.
    XCTAssertTrue([self.scheduler shouldScanForTrigger:CDRScanTriggerTimer now:[self after:45]]);
    // 10s: still inside the floor.
    XCTAssertFalse([self.scheduler shouldScanForTrigger:CDRScanTriggerTimer now:[self after:10]]);
}

@end
