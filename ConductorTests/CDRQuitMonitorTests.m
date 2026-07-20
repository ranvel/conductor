//
//  CDRQuitMonitorTests.m
//  ConductorTests
//
//  The observe-only mode backing "update on quit": completion when nothing is
//  running, and silence after cancellation. (Real-termination observation is
//  exercised by the manual update-on-quit drill; launching apps from unit
//  tests is flaky.)
//

#import <XCTest/XCTest.h>
#import "CDRQuitMonitor.h"

@interface CDRQuitMonitorTests : XCTestCase
@end

@implementation CDRQuitMonitorTests

- (void)testObserveCompletesImmediatelyWhenNothingIsRunning {
    CDRQuitMonitor *monitor = [[CDRQuitMonitor alloc] init];
    XCTestExpectation *done = [self expectationWithDescription:@"observe completion"];
    [monitor observeTerminationOfBundleID:@"com.example.never-running-app"
                               completion:^{
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:2.0];
}

- (void)testCancelObservationPreventsCompletion {
    CDRQuitMonitor *monitor = [[CDRQuitMonitor alloc] init];
    XCTestExpectation *never = [self expectationWithDescription:@"completion must not fire"];
    never.inverted = YES;
    [monitor observeTerminationOfBundleID:@"com.example.never-running-app"
                               completion:^{
        [never fulfill];
    }];
    // Cancel before the main queue drains the zero-running fast path.
    [monitor cancelObservation];
    [self waitForExpectations:@[never] timeout:1.0];
}

@end
