//
//  CDRRetractionDrillIntegrationTests.m
//  ConductorTests
//
//  The M2 acceptance drill (roadmap.md): drive fetcher → policy → store
//  against the live harness, flipping manifests the way a vendor would.
//  Each "check" builds a fresh store instance from the same directory, so
//  persistence across app launches is exercised, not simulated.
//
//  Requires TestHarness/build-testee.sh (the M2 version, which emits
//  manifest-retracted.json / manifest-urgent.json / ConductorTestee-1.1.app);
//  tests skip when artifacts are absent.
//

#import <XCTest/XCTest.h>
#import "CDRAppRegistration.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRUpdateOperation.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdateStateStore.h"
#import "CDRErrors.h"

static NSString * const kTesteeBundleID = @"com.ranvel.conductor-testee";
/// NOT 8000: Xcode runs test classes in parallel processes, and
/// CDRUpdateOperationIntegrationTests owns 8000. Every drill rewrites the
/// app's conductor.json to this port, and no drill dereferences a manifest's
/// artifact URL (the one operation run aborts at the pre-download re-check),
/// so the serve fixtures' baked-in :8000 URLs are never fetched.
static const int kPort = 8001;

#pragma mark - Minimal operation delegate

@interface CDRRetractionDrillDelegate : NSObject <CDRUpdateOperationDelegate>
@property (nonatomic, copy) void (^onFinish)(NSError *error);
@end

@implementation CDRRetractionDrillDelegate
- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase {}
- (void)updateOperation:(CDRUpdateOperation *)op
    requestsQuitDecisionFor:(NSArray<NSRunningApplication *> *)apps
                      reply:(void (^)(BOOL))reply {
    reply(YES);
}
- (void)updateOperation:(CDRUpdateOperation *)op
     didFinishWithError:(NSError *)error
       appWasQuitByFlow:(BOOL)wasQuit {
    if (self.onFinish) self.onFinish(error);
}
@end

@interface CDRRetractionDrillIntegrationTests : XCTestCase
@property (nonatomic) NSURL *serveDir;
@property (nonatomic) NSTask *server;
@property (nonatomic) NSURL *appsDir;      // stand-in for /Applications
@property (nonatomic) NSURL *installedApp; // v1.0
@property (nonatomic) NSURL *stateDir;
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) CDRManifestFetcher *fetcher;
@end

@implementation CDRRetractionDrillIntegrationTests

- (void)setUp {
    self.continueAfterFailure = NO;

    NSURL *repoRoot = [[[NSURL fileURLWithPath:@(__FILE__)]
        URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    self.serveDir = [repoRoot URLByAppendingPathComponent:@"TestHarness/serve" isDirectory:YES];

    NSURL *v10 = [self.serveDir URLByAppendingPathComponent:@"ConductorTestee-1.0.app"];
    NSURL *retracted = [self.serveDir URLByAppendingPathComponent:@"manifest-retracted.json"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:v10.path] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:retracted.path]) {
        self.serveDir = nil; // tests will skip (stale serve/ lacks M2 fixtures)
        return;
    }

    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDRRetractionDrill-%@", NSUUID.UUID.UUIDString]];
    self.appsDir = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Applications"] isDirectory:YES];
    self.stateDir = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"State"] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.appsDir
                             withIntermediateDirectories:YES attributes:nil error:NULL];

    self.installedApp = [self.appsDir URLByAppendingPathComponent:@"ConductorTestee.app"];
    [self ditto:v10 to:self.installedApp];

    self.session = [CDRDevModeSession sessionFromArguments:
        @[@"conductor", @"--dev-mode", kTesteeBundleID] error:NULL];
    XCTAssertNotNil(self.session);
    self.fetcher = [[CDRManifestFetcher alloc] initWithSession:self.session];

    [self startServer];
}

- (void)tearDown {
    [self.server terminate];
    self.server = nil;
    if (self.appsDir) {
        [[NSFileManager defaultManager] removeItemAtURL:
            self.appsDir.URLByDeletingLastPathComponent error:NULL];
    }
}

- (void)startServer {
    self.server = [[NSTask alloc] init];
    self.server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
    self.server.arguments = @[@"-m", @"http.server", [NSString stringWithFormat:@"%d", kPort],
                              @"--bind", @"127.0.0.1"];
    self.server.currentDirectoryURL = self.serveDir;
    self.server.standardOutput = [NSPipe pipe];
    self.server.standardError = [NSPipe pipe];
    NSError *error = nil;
    XCTAssertTrue([self.server launchAndReturnError:&error], @"%@", error);

    NSURL *probe = [NSURL URLWithString:
        [NSString stringWithFormat:@"http://127.0.0.1:%d/manifest.json", kPort]];
    for (int i = 0; i < 50; i++) {
        NSData *data = [NSData dataWithContentsOfURL:probe];
        if (data.length > 0) return;
        usleep(100000);
    }
    XCTFail(@"local http.server did not come up on port %d", kPort);
}

#pragma mark - Helpers

- (void)ditto:(NSURL *)from to:(NSURL *)to {
    NSTask *copy = [[NSTask alloc] init];
    copy.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    copy.arguments = @[from.path, to.path];
    [copy launchAndReturnError:NULL];
    [copy waitUntilExit];
    XCTAssertEqual(copy.terminationStatus, 0);
}

/// Points the app's conductor.json at the named manifest fixture — the
/// vendor "swapping the manifest." Test-only mutation; breaks the seal, which
/// is fine (the installed copy's signature is only read for its Team ID).
- (void)pointApp:(NSURL *)appURL atManifest:(NSString *)name {
    NSURL *jsonURL = [appURL URLByAppendingPathComponent:
        [CDRAppRegistration conductorJSONRelativePath]];
    NSString *json = [NSString stringWithFormat:
        @"{\"conductor\":1,\"update_url\":\"http://127.0.0.1:%d/%@\","
        @"\"vendor_url\":\"http://127.0.0.1:%d/\"}", kPort, name, kPort];
    XCTAssertTrue([json writeToURL:jsonURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

- (CDRAppRegistration *)registrationForApp:(NSURL *)appURL {
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNotNil(reg, @"%@", error);
    return reg;
}

/// One "check": fetch the live manifest, run the policy against the persisted
/// state, persist the outcome. A fresh store instance per call makes each
/// check behave like a new app launch.
- (CDRUpdateDecision *)checkApp:(NSURL *)appURL
                           soak:(CDRSoakDuration)soak
                   breakThrough:(BOOL)breakThrough {
    CDRAppRegistration *reg = [self registrationForApp:appURL];

    XCTestExpectation *done = [self expectationWithDescription:@"fetch"];
    __block CDRManifest *manifest = nil;
    __block NSError *fetchError = nil;
    [self.fetcher fetchManifestForRegistration:reg completion:^(CDRManifest *m, NSError *e) {
        manifest = m;
        fetchError = e;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:30];
    XCTAssertNotNil(manifest, @"%@", fetchError);

    CDRUpdateStateStore *store = [[CDRUpdateStateStore alloc] initWithDirectoryURL:self.stateDir
                                                                               now:[NSDate date]];
    CDRUpdateDecision *decision = [CDRUpdatePolicy decisionForRegistration:reg
                                                                  manifest:manifest
                                                                     state:[store stateForBundleID:reg.bundleID]
                                                              soakDuration:soak
                                                              breakThrough:breakThrough
                                                                       now:[NSDate date]];
    [store putState:decision.stateAfterCheck];
    return decision;
}

- (CDRAppUpdateState *)persistedState {
    CDRUpdateStateStore *store = [[CDRUpdateStateStore alloc] initWithDirectoryURL:self.stateDir
                                                                               now:[NSDate date]];
    return [store stateForBundleID:kTesteeBundleID];
}

#pragma mark - The drills

- (void)testStateADrill_PromoteNotifyRetract {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh (M2) first"); }

    // Promote: 1.1 is advertised, soak off → surfaced and remembered.
    [self pointApp:self.installedApp atManifest:@"manifest.json"];
    CDRUpdateDecision *first = [self checkApp:self.installedApp soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(first.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertEqualObjects([self persistedState].lastNotifiedVersion, @"1.1");

    // Retract: the vendor swaps the manifest back to 1.0 → State A, loud
    // once, promise cleared in the persisted state.
    [self pointApp:self.installedApp atManifest:@"manifest-retracted.json"];
    CDRUpdateDecision *second = [self checkApp:self.installedApp soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(second.outcome, CDRUpdateOutcomeRetractedPending);
    XCTAssertEqualObjects(second.retractedVersion, @"1.1");
    XCTAssertNil([self persistedState].lastNotifiedVersion);

    // Third check: the loudness was one-time — now it's just up to date.
    CDRUpdateDecision *third = [self checkApp:self.installedApp soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(third.outcome, CDRUpdateOutcomeUpToDate);
}

- (void)testStateBDrill_InstallFirstThenRetract {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh (M2) first"); }

    // Promote + notify against the v1.0 install.
    [self pointApp:self.installedApp atManifest:@"manifest.json"];
    CDRUpdateDecision *first = [self checkApp:self.installedApp soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(first.outcome, CDRUpdateOutcomeAvailable);

    // Simulate the completed install (the swap itself is M1-tested) at a
    // fresh path — NSBundle caches Info.plist by path, so ditto-ing v1.1
    // over the old copy would read back stale versions.
    NSURL *upgraded = [self.appsDir URLByAppendingPathComponent:@"ConductorTestee-upgraded.app"];
    [self ditto:[self.serveDir URLByAppendingPathComponent:@"ConductorTestee-1.1.app"] to:upgraded];

    // Retract: manifest back to 1.0 while 1.1 is installed → State B,
    // persisting check after check (inform, never auto-downgrade).
    [self pointApp:upgraded atManifest:@"manifest-retracted.json"];
    CDRUpdateDecision *second = [self checkApp:upgraded soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(second.outcome, CDRUpdateOutcomeRetractedInstalled);
    XCTAssertEqualObjects(second.retractedVersion, @"1.1");
    XCTAssertEqualObjects([self persistedState].lastNotifiedVersion, @"1.1", @"retained — gate must keep firing");

    CDRUpdateDecision *third = [self checkApp:upgraded soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(third.outcome, CDRUpdateOutcomeRetractedInstalled);

    // The vendor re-promotes 1.1 → the state resolves quietly.
    [self pointApp:upgraded atManifest:@"manifest.json"];
    CDRUpdateDecision *fourth = [self checkApp:upgraded soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(fourth.outcome, CDRUpdateOutcomeUpToDate);
}

- (void)testSoakAndUrgencyDrill {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh (M2) first"); }

    // Under a 1-week soak, a freshly observed 1.1 is hidden.
    [self pointApp:self.installedApp atManifest:@"manifest.json"];
    CDRUpdateDecision *deferred = [self checkApp:self.installedApp soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(deferred.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertNotNil(deferred.deferredUntil);
    XCTAssertNil([self persistedState].lastNotifiedVersion);

    // Check Now on the app offers it honestly, without marking it notified.
    CDRUpdateDecision *offered = [self checkApp:self.installedApp soak:CDRSoakDurationOneWeek breakThrough:YES];
    XCTAssertEqual(offered.outcome, CDRUpdateOutcomeDeferredOffered);
    XCTAssertNil([self persistedState].lastNotifiedVersion);

    // The vendor flags the same build data_loss → soak bypassed, surfaced,
    // and now remembered as notified.
    [self pointApp:self.installedApp atManifest:@"manifest-urgent.json"];
    CDRUpdateDecision *urgent = [self checkApp:self.installedApp soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(urgent.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertEqual(urgent.urgency, CDRUrgencyDataLoss);
    XCTAssertEqualObjects([self persistedState].lastNotifiedVersion, @"1.1");
}

- (void)testLastMomentRecheckClearsNotifiedState {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh (M2) first"); }

    // Notify 1.1, then have the vendor pull it before the user clicks
    // install. The operation's pre-download re-check refuses; the app layer's
    // reaction (clear the notified memory — same call AppDelegate makes) is
    // what turns the refusal into a resolved State A.
    [self pointApp:self.installedApp atManifest:@"manifest.json"];
    CDRUpdateDecision *first = [self checkApp:self.installedApp soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(first.outcome, CDRUpdateOutcomeAvailable);
    CDRManifest *shown = nil;
    {
        NSData *data = [NSData dataWithContentsOfURL:
            [self.serveDir URLByAppendingPathComponent:@"manifest.json"]];
        shown = [CDRManifest manifestWithData:data error:NULL];
    }
    XCTAssertNotNil(shown);

    [self pointApp:self.installedApp atManifest:@"manifest-downgrade.json"];

    XCTestExpectation *finished = [self expectationWithDescription:@"operation finished"];
    __block NSError *finishError = nil;
    CDRRetractionDrillDelegate *delegate = [[CDRRetractionDrillDelegate alloc] init];
    delegate.onFinish = ^(NSError *error) {
        finishError = error;
        [finished fulfill];
    };
    CDRUpdateOperation *op = [[CDRUpdateOperation alloc]
        initWithRegistration:[self registrationForApp:self.installedApp]
                    manifest:shown
                     session:self.session
                    delegate:delegate];
    [op start];
    [self waitForExpectations:@[finished] timeout:120];

    XCTAssertEqual(finishError.code, CDRErrorDowngradeRefused);

    // The AppDelegate reaction to that refusal:
    CDRUpdateStateStore *store = [[CDRUpdateStateStore alloc] initWithDirectoryURL:self.stateDir
                                                                               now:[NSDate date]];
    [store clearNotifiedVersionForBundleID:kTesteeBundleID at:[NSDate date]];
    XCTAssertNil([self persistedState].lastNotifiedVersion);
}

@end
