//
//  CDRUpdateOperationIntegrationTests.m
//  ConductorTests
//
//  Drives the full engine against TestHarness/serve over a local HTTP server
//  (dev-mode session). Requires TestHarness/build-testee.sh to have been run;
//  tests skip when the artifacts are absent.
//
//  The artifacts are Developer ID-signed but (until notary credentials are
//  stored) NOT notarized, so the "positive" path is expected to march through
//  fetch → download → sha256 → extract → bundle-ID → version → Team ID
//  pinning and refuse at the notarization step — every earlier stage proven,
//  verification never relaxed. When notarized artifacts are present
//  (stapled), the same test passes end-to-end through the swap.
//

#import <XCTest/XCTest.h>
#import "CDRAppRegistration.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRUpdateOperation.h"
#import "CDRNotarizationCheck.h"
#import "CDRQuarantine.h"
#import "CDRErrors.h"
#import "CDRInternetAccessPolicy.h"
#import "CDRNetworkInspection.h"
#import "CDRUpdatePreferences.h"

static NSString * const kTesteeBundleID = @"com.ranvel.conductor-testee";
static const int kPort = 8000;

#pragma mark - Delegate recorder

@interface CDRIntegrationDelegate : NSObject <CDRUpdateOperationDelegate>
@property (nonatomic) NSMutableArray<NSNumber *> *phases;
@property (nonatomic) NSMutableArray<NSString *> *logs;
@property (nonatomic, nullable) NSError *finishError;
@property (nonatomic) XCTestExpectation *finished;
/// The reply the recorder gives when the operation asks about a running app.
@property (nonatomic) CDRQuitDecision quitDecision; // default QuitAndUpdate
@property (nonatomic) BOOL wasQuitByFlow;
@end

@implementation CDRIntegrationDelegate
- (instancetype)init {
    self = [super init];
    _phases = [NSMutableArray array];
    _logs = [NSMutableArray array];
    return self;
}
- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase {
    [self.phases addObject:@(phase)];
}
- (void)updateOperation:(CDRUpdateOperation *)op logMessage:(NSString *)message {
    [self.logs addObject:message];
}
- (void)updateOperation:(CDRUpdateOperation *)op
    requestsQuitDecisionFor:(NSArray<NSRunningApplication *> *)apps
                      reply:(void (^)(CDRQuitDecision))reply {
    reply(self.quitDecision); // testee is never running during tests, but be permissive
}
- (void)updateOperation:(CDRUpdateOperation *)op
     didFinishWithError:(NSError *)error
       appWasQuitByFlow:(BOOL)wasQuit {
    self.finishError = error;
    self.wasQuitByFlow = wasQuit;
    [self.finished fulfill];
}
- (BOOL)sawPhase:(CDRUpdatePhase)phase {
    return [self.phases containsObject:@(phase)];
}
@end

/// A delegate that takes part in the Inspect step (CND-7): records what the
/// operation learned and answers as told.
typedef NS_ENUM(NSInteger, CDRInspectAnswer) {
    CDRInspectAnswerApprove = 0,
    CDRInspectAnswerDecline,
    /// Keep the operation parked; the test answers (or cancels) later.
    CDRInspectAnswerHold,
};

@interface CDRInspectingDelegate : CDRIntegrationDelegate
@property (nonatomic) CDRInspectAnswer answer;
@property (nonatomic, nullable) CDRNetworkInspection *inspection;
@property (nonatomic) NSUInteger inspectCount;
@property (nonatomic, copy, nullable) void (^heldReply)(BOOL);
@property (nonatomic, nullable) XCTestExpectation *inspected;
@end

@implementation CDRInspectingDelegate
- (void)updateOperation:(CDRUpdateOperation *)op
             didInspect:(CDRNetworkInspection *)inspection
                  reply:(void (^)(BOOL))reply {
    self.inspection = inspection;
    self.inspectCount++;
    switch (self.answer) {
        case CDRInspectAnswerApprove: reply(YES); break;
        case CDRInspectAnswerDecline: reply(NO); break;
        case CDRInspectAnswerHold: self.heldReply = reply; break;
    }
    [self.inspected fulfill];
}
@end

#pragma mark - Tests

@interface CDRUpdateOperationIntegrationTests : XCTestCase
@property (nonatomic) NSURL *serveDir;
@property (nonatomic) NSTask *server;
@property (nonatomic) NSURL *appsDir;      // stand-in for /Applications
@property (nonatomic) NSURL *installedApp;
@property (nonatomic) CDRDevModeSession *session;
@end

@implementation CDRUpdateOperationIntegrationTests

- (void)setUp {
    self.continueAfterFailure = NO;

    // TestHarness/serve relative to this source file's repo.
    NSURL *repoRoot = [[[NSURL fileURLWithPath:@(__FILE__)]
        URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    self.serveDir = [repoRoot URLByAppendingPathComponent:@"TestHarness/serve" isDirectory:YES];

    NSURL *v10 = [self.serveDir URLByAppendingPathComponent:@"ConductorTestee-1.0.app"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:v10.path]) {
        self.serveDir = nil; // tests will skip
        return;
    }

    // Fake /Applications on the same volume as the real temp dir.
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDRIntegration-%@", NSUUID.UUID.UUIDString]];
    self.appsDir = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Applications"] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.appsDir
                             withIntermediateDirectories:YES attributes:nil error:NULL];

    self.installedApp = [self.appsDir URLByAppendingPathComponent:@"ConductorTestee.app"];
    NSTask *copy = [[NSTask alloc] init];
    copy.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    copy.arguments = @[v10.path, self.installedApp.path];
    [copy launchAndReturnError:NULL];
    [copy waitUntilExit];
    XCTAssertEqual(copy.terminationStatus, 0);

    self.session = [CDRDevModeSession sessionFromArguments:
        @[@"conductor", @"--dev-mode", kTesteeBundleID] error:NULL];
    XCTAssertNotNil(self.session);

    [self startServer];
}

- (void)tearDown {
    // The update-on-quit drills launch the testee; never leave one behind.
    // (forceTerminate is fine in test cleanup — the polite-only rule binds the
    // engine, not the harness.)
    for (NSRunningApplication *app in
         [NSRunningApplication runningApplicationsWithBundleIdentifier:kTesteeBundleID]) {
        [app forceTerminate];
    }
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

    // Wait until the server responds.
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

- (CDRAppRegistration *)registration {
    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:self.installedApp error:&error];
    XCTAssertNotNil(reg, @"%@", error);
    return reg;
}

- (nullable CDRManifest *)manifestNamed:(NSString *)name {
    NSData *data = [NSData dataWithContentsOfURL:
        [self.serveDir URLByAppendingPathComponent:name]];
    return [CDRManifest manifestWithData:data error:NULL];
}

- (CDRIntegrationDelegate *)runOperationWithManifest:(CDRManifest *)manifest {
    CDRIntegrationDelegate *delegate = [[CDRIntegrationDelegate alloc] init];
    delegate.finished = [self expectationWithDescription:@"operation finished"];
    CDRUpdateOperation *op = [[CDRUpdateOperation alloc] initWithRegistration:[self registration]
                                                                     manifest:manifest
                                                                      session:self.session
                                                                     delegate:delegate];
    [op start];
    [self waitForExpectations:@[delegate.finished] timeout:120];
    return delegate;
}

- (BOOL)stagingIsGone {
    NSURL *stagingRoot = [self.appsDir URLByAppendingPathComponent:@".conductor-staging"];
    return ![[NSFileManager defaultManager] fileExistsAtPath:
        [stagingRoot URLByAppendingPathComponent:kTesteeBundleID].path];
}

- (NSString *)installedVersion {
    NSBundle *bundle = [NSBundle bundleWithURL:self.installedApp];
    // NSBundle caches by path; read the plist directly to see post-swap state.
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:
        [self.installedApp URLByAppendingPathComponent:@"Contents/Info.plist"]];
    (void)bundle;
    return info[@"CFBundleShortVersionString"];
}

#pragma mark - The runs

- (void)testFullPipelineAgainstLocalServer {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    CDRManifest *manifest = [self manifestNamed:@"manifest.json"];
    XCTAssertNotNil(manifest);

    // Is the artifact actually notarized (built with --notarize)? Assess a
    // scratch extraction honestly rather than assuming.
    BOOL notarized = [CDRNotarizationCheck assessBundleAtURL:self.installedApp error:NULL];

    CDRIntegrationDelegate *d = [self runOperationWithManifest:manifest];

    XCTAssertTrue([d sawPhase:CDRUpdatePhaseFetching]);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseDownloading]);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseExtracting]);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseVerifying]);
    // A delegate that takes no part in inspection never sees the phase: the
    // pipeline is exactly what it was before the network gate existed.
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseInspecting]);

    if (notarized) {
        XCTAssertNil(d.finishError, @"full positive path: %@", d.finishError);
        XCTAssertEqualObjects([self installedVersion], @"1.1", @"swap happened");
        XCTAssertFalse([CDRQuarantine treeContainsQuarantineAtURL:self.installedApp]);
    } else {
        // Signed-but-unnotarized: every stage before notarization passed —
        // the log proves signature+team pinning ran — then a clean refusal.
        XCTAssertEqual(d.finishError.code, CDRErrorNotarizationRejected);
        XCTAssertEqualObjects([self installedVersion], @"1.0", @"installed app untouched");
        BOOL sawPinLog = NO;
        for (NSString *line in d.logs) {
            if ([line containsString:@"signature valid for pinned Team ID F252L9GUBW"]) sawPinLog = YES;
        }
        XCTAssertTrue(sawPinLog, @"Team ID pinning ran before the notarization refusal. Logs: %@", d.logs);
    }
    XCTAssertTrue([self stagingIsGone], @"staging cleaned either way");
}

- (void)testDowngradeManifestIsRefusedBeforeDownload {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    // The retraction last-moment re-check (retraction.md): the user was shown
    // 1.1, but by install time the vendor has recalled it — the fresh fetch
    // (conductor.json now points at manifest-downgrade.json, advertising 0.9)
    // regresses below the shown version and must abort before any download.
    // Rewriting the installed app's conductor.json is a test-only mutation; it
    // breaks the app's seal, which is fine — the INSTALLED copy's signature is
    // only read for its Team ID, not validated (replace-flow §0).
    CDRManifest *shown = [self manifestNamed:@"manifest.json"];
    XCTAssertNotNil(shown);

    NSURL *jsonURL = [self.installedApp URLByAppendingPathComponent:
        [CDRAppRegistration conductorJSONRelativePath]];
    NSString *json = [NSString stringWithFormat:
        @"{\"conductor\":1,\"update_url\":\"http://127.0.0.1:%d/manifest-downgrade.json\"}", kPort];
    XCTAssertTrue([json writeToURL:jsonURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    CDRIntegrationDelegate *d = [self runOperationWithManifest:shown];
    XCTAssertNotNil(d.finishError);
    XCTAssertEqual(d.finishError.code, CDRErrorDowngradeRefused);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseDownloading], @"aborted before any download");
    XCTAssertEqualObjects([self installedVersion], @"1.0", @"installed app untouched");
    XCTAssertTrue([self stagingIsGone]);
}

- (void)testWrongBundleIDManifestIsRefused {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    // Fetch path: the fetcher itself must refuse a manifest whose bundle_id
    // doesn't match the registration, before any download.
    NSURL *jsonURL = [self.installedApp URLByAppendingPathComponent:
        [CDRAppRegistration conductorJSONRelativePath]];
    NSString *json = [NSString stringWithFormat:
        @"{\"conductor\":1,\"update_url\":\"http://127.0.0.1:%d/manifest-wrong-bundle.json\"}", kPort];
    XCTAssertTrue([json writeToURL:jsonURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    CDRManifestFetcher *fetcher = [[CDRManifestFetcher alloc] initWithSession:self.session];
    XCTestExpectation *done = [self expectationWithDescription:@"fetch"];
    __block NSError *fetchError = nil;
    __block CDRManifest *fetched = nil;
    [fetcher fetchManifestForRegistration:[self registration]
                               completion:^(CDRManifest *manifest, NSError *error) {
        fetched = manifest;
        fetchError = error;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:30];
    XCTAssertNil(fetched);
    XCTAssertEqual(fetchError.code, CDRErrorBundleIDManifestMismatch);
}

- (void)testHarnessManifestExercisesReleaseNoteRules {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    // The real fetch path, against the manifest build-testee.sh wrote
    // (spec.md §3.5): typed notes, an unknown type, a forged "retracted",
    // and a history with entries on both sides of the installed version.
    CDRManifestFetcher *fetcher = [[CDRManifestFetcher alloc] initWithSession:self.session];
    XCTestExpectation *done = [self expectationWithDescription:@"fetch"];
    __block CDRManifest *manifest = nil;
    [fetcher fetchManifestForRegistration:[self registration]
                               completion:^(CDRManifest *fetched, NSError *error) {
        manifest = fetched;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:30];
    XCTAssertNotNil(manifest);

    CDRRelease *advertised = manifest.advertisedRelease;
    XCTAssertEqualObjects(advertised.version, @"1.1");
    XCTAssertNotNil(advertised.date);
    XCTAssertGreaterThan(manifest.artifactSize.longLongValue, 0);

    // All seven developer types, grouped in the fixed order although the
    // manifest lists them backwards; two "fixed" items share one group.
    XCTAssertEqual(advertised.typeSet, CDRReleaseNoteTypeSetDeveloperAuthored);
    NSArray<CDRReleaseNoteGroup *> *groups = advertised.groups;
    XCTAssertEqual(groups.count, 7u);
    for (NSUInteger i = 0; i < groups.count; i++) {
        XCTAssertEqual(groups[i].type, (CDRReleaseNoteType)i);
    }
    XCTAssertEqual(groups.lastObject.notes.count, 2u);

    // The unknown type and the forged "retracted": dropped, logged, counted.
    XCTAssertEqual(advertised.notes.count, 8u);
    XCTAssertEqual(advertised.undisplayableNoteCount, 2u);
    XCTAssertEqual(manifest.parseWarnings.count, 2u);

    // History: 1.0.5 is the only entry strictly between installed (1.0) and
    // advertised (1.1).
    NSArray<CDRRelease *> *releases =
        [manifest releasesNewerThanVersion:[self registration].installedShortVersion];
    XCTAssertEqualObjects([releases valueForKey:@"version"], (@[@"1.1", @"1.0.5"]));
    XCTAssertEqual(releases.lastObject.notes.count, 2u);
}

- (void)testReplayOfOlderSignedBuildIsRefused {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    // manifest-replay.json advertises "1.2" but its artifact is the v1.0
    // build — a hijacked-manifest replay of an older validly-signed binary.
    // The staged Info.plist (1.0 vs installed 1.0) fails strict-newer.
    NSURL *jsonURL = [self.installedApp URLByAppendingPathComponent:
        [CDRAppRegistration conductorJSONRelativePath]];
    NSString *json = [NSString stringWithFormat:
        @"{\"conductor\":1,\"update_url\":\"http://127.0.0.1:%d/manifest-replay.json\"}", kPort];
    XCTAssertTrue([json writeToURL:jsonURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    CDRManifest *replay = [self manifestNamed:@"manifest-replay.json"];
    CDRIntegrationDelegate *d = [self runOperationWithManifest:replay];
    XCTAssertNotNil(d.finishError);
    XCTAssertEqual(d.finishError.code, CDRErrorNotAnUpgrade,
        @"staged 1.0 vs installed 1.0 is not an upgrade — manifest's claimed 1.2 was never trusted");
    XCTAssertEqualObjects([self installedVersion], @"1.0");
    XCTAssertTrue([self stagingIsGone]);
}

- (void)testAdHocSignedArtifactFailsTeamPinning {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    NSURL *jsonURL = [self.installedApp URLByAppendingPathComponent:
        [CDRAppRegistration conductorJSONRelativePath]];
    NSString *json = [NSString stringWithFormat:
        @"{\"conductor\":1,\"update_url\":\"http://127.0.0.1:%d/manifest-adhoc.json\"}", kPort];
    XCTAssertTrue([json writeToURL:jsonURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);

    CDRManifest *adhoc = [self manifestNamed:@"manifest-adhoc.json"];
    CDRIntegrationDelegate *d = [self runOperationWithManifest:adhoc];
    XCTAssertNotNil(d.finishError);
    XCTAssertTrue(d.finishError.code == CDRErrorTeamIDMismatch ||
                  d.finishError.code == CDRErrorSignatureInvalid,
        @"ad-hoc artifact must fail pinned validation, got %@", d.finishError);
    XCTAssertEqualObjects([self installedVersion], @"1.0");
    XCTAssertTrue([self stagingIsGone]);
}

#pragma mark - Update on quit

/// Launches the temp-installed testee and waits until it registers as running.
- (void)launchInstalledTestee {
    XCTestExpectation *launched = [self expectationWithDescription:@"testee launched"];
    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    config.activates = NO;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:self.installedApp
                                          configuration:config
                                      completionHandler:^(NSRunningApplication *app, NSError *error) {
        XCTAssertNotNil(app, @"testee failed to launch: %@", error);
        [launched fulfill];
    }];
    [self waitForExpectations:@[launched] timeout:30];

    XCTestExpectation *running = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
            return [NSRunningApplication runningApplicationsWithBundleIdentifier:kTesteeBundleID].count > 0;
        }] object:nil];
    [self waitForExpectations:@[running] timeout:30];
}

/// Starts an operation that replies UpdateOnQuit and waits until it parks.
/// Both drills need artifacts that pass the notarization gate — parking
/// happens after verification, so they skip on unnotarized builds (same
/// auto-detect as the positive-path test).
- (nullable CDRIntegrationDelegate *)startParkedOperation:(CDRUpdateOperation **)outOp {
    CDRManifest *manifest = [self manifestNamed:@"manifest.json"];
    XCTAssertNotNil(manifest);

    [self launchInstalledTestee];

    CDRIntegrationDelegate *delegate = [[CDRIntegrationDelegate alloc] init];
    delegate.quitDecision = CDRQuitDecisionUpdateOnQuit;
    delegate.finished = [self expectationWithDescription:@"operation finished"];
    CDRUpdateOperation *op = [[CDRUpdateOperation alloc] initWithRegistration:[self registration]
                                                                     manifest:manifest
                                                                      session:self.session
                                                                     delegate:delegate];
    [op start];

    XCTestExpectation *parked = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
            return op.parkedAwaitingQuit;
        }] object:nil];
    [self waitForExpectations:@[parked] timeout:120];
    XCTAssertTrue([delegate sawPhase:CDRUpdatePhaseAwaitingQuit]);
    if (outOp) *outOp = op;
    return delegate;
}

- (void)testUpdateOnQuitParksThenSwapsWhenAppExits {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }
    if (![CDRNotarizationCheck assessBundleAtURL:self.installedApp error:NULL]) {
        XCTSkip(@"parking happens past the notarization gate — needs build-testee.sh --notarize");
    }

    CDRUpdateOperation *op = nil;
    CDRIntegrationDelegate *d = [self startParkedOperation:&op];

    // The user quits the app themselves; the parked operation observes the
    // termination and proceeds to the swap.
    for (NSRunningApplication *app in
         [NSRunningApplication runningApplicationsWithBundleIdentifier:kTesteeBundleID]) {
        [app terminate];
    }
    [self waitForExpectations:@[d.finished] timeout:120];

    XCTAssertNil(d.finishError, @"parked swap failed: %@", d.finishError);
    XCTAssertFalse(d.wasQuitByFlow, @"the flow did not quit the app — no relaunch offer");
    XCTAssertEqualObjects([self installedVersion], @"1.1", @"swap happened after the quit");
    XCTAssertTrue([self stagingIsGone]);
}

- (void)testCancelParkedUpdateLeavesEverythingUntouched {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }
    if (![CDRNotarizationCheck assessBundleAtURL:self.installedApp error:NULL]) {
        XCTSkip(@"parking happens past the notarization gate — needs build-testee.sh --notarize");
    }

    CDRUpdateOperation *op = nil;
    CDRIntegrationDelegate *d = [self startParkedOperation:&op];

    [op cancelParkedUpdate];
    [self waitForExpectations:@[d.finished] timeout:30];

    XCTAssertEqual(d.finishError.code, CDRErrorUpdateCancelled);
    XCTAssertEqualObjects([self installedVersion], @"1.0", @"installed app untouched");
    XCTAssertTrue([self stagingIsGone], @"staging cleaned on cancellation");
    XCTAssertEqual([NSRunningApplication runningApplicationsWithBundleIdentifier:kTesteeBundleID].count,
                   1u, @"the running app was never touched");
}

- (void)testDeadServerFailsCleanly {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }

    CDRManifest *manifest = [self manifestNamed:@"manifest.json"];
    [self.server terminate];
    [self.server waitUntilExit];
    self.server = nil;

    CDRIntegrationDelegate *d = [self runOperationWithManifest:manifest];
    XCTAssertNotNil(d.finishError);
    XCTAssertEqual(d.finishError.code, CDRErrorManifestUnreachable);
    XCTAssertEqualObjects([self installedVersion], @"1.0");
    XCTAssertTrue([self stagingIsGone]);
}

#pragma mark - Network gate (CND-7)

/// Points the installed copy's conductor.json at one of the harness manifests,
/// so the operation's last-moment re-fetch sees the same version it was given.
- (void)pointInstalledAppAtManifest:(NSString *)name {
    NSURL *jsonURL = [self.installedApp URLByAppendingPathComponent:[CDRAppRegistration conductorJSONRelativePath]];
    NSString *json = [NSString stringWithFormat:@"{\"conductor\":1,\"update_url\":\"http://127.0.0.1:%d/%@\"}", kPort, name];
    XCTAssertTrue([json writeToURL:jsonURL atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

/// The network-gate builds only exist after a harness run that made them,
/// and Inspect sits behind the notarization check.
- (BOOL)networkGateArtifactsAreUsable {
    if (!self.serveDir) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:
          [self.serveDir URLByAppendingPathComponent:@"manifest-1.2.json"].path]) return NO;
    return [CDRNotarizationCheck assessBundleAtURL:self.installedApp error:NULL];
}

- (CDRInspectingDelegate *)runInspectingOperationWithManifest:(CDRManifest *)manifest answer:(CDRInspectAnswer)answer {
    CDRInspectingDelegate *delegate = [[CDRInspectingDelegate alloc] init];
    delegate.answer = answer;
    delegate.finished = [self expectationWithDescription:@"operation finished"];
    CDRUpdateOperation *op = [[CDRUpdateOperation alloc] initWithRegistration:[self registration]
                                                                     manifest:manifest
                                                                      session:self.session
                                                                     delegate:delegate];
    [op start];
    [self waitForExpectations:@[delegate.finished] timeout:120];
    return delegate;
}

static CDRUpdatePreferences *GatePreferences(BOOL policyExempts) {
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    prefs.requireNetworkApproval = YES;
    prefs.policyExemptsApproval = policyExempts;
    return [prefs copy];
}

- (void)testBuildThatGainsAccessWithAPolicyIsInspectedAfterVerifyAndInstallsOnApproval {
    if (![self networkGateArtifactsAreUsable]) { XCTSkip(@"needs build-testee.sh --notarize (v1.2)"); }
    [self pointInstalledAppAtManifest:@"manifest-1.2.json"];

    CDRInspectingDelegate *d = [self runInspectingOperationWithManifest:[self manifestNamed:@"manifest-1.2.json"]
                                                                 answer:CDRInspectAnswerApprove];

    // Inspect came after Verify, once.
    XCTAssertEqual(d.inspectCount, 1u);
    NSUInteger verify = [d.phases indexOfObject:@(CDRUpdatePhaseVerifying)];
    NSUInteger inspect = [d.phases indexOfObject:@(CDRUpdatePhaseInspecting)];
    XCTAssertNotEqual(inspect, (NSUInteger)NSNotFound);
    XCTAssertLessThan(verify, inspect);

    // What it read, from the signed bundles themselves.
    CDRNetworkInspection *inspection = d.inspection;
    XCTAssertEqualObjects(inspection.installedVersion, @"1.0");
    XCTAssertEqualObjects(inspection.stagedVersion, @"1.2");
    XCTAssertEqual(inspection.installedPosture, CDRNetworkPostureNone);
    XCTAssertEqual(inspection.stagedPosture, CDRNetworkPostureClient);
    XCTAssertEqual(inspection.change, CDRNetworkChangeGained);
    XCTAssertEqualObjects(inspection.addedEntitlements, (@[CDREntitlementNetworkClient]));
    XCTAssertEqualObjects(inspection.teamID, @"F252L9GUBW");

    // The policy, from under the staged build's seal: the wildcard in
    // Conductor's words, the second purpose resolved through the bundle's
    // .strings table, the host-less entry dropped, the service not shown.
    XCTAssertTrue(inspection.hasPolicy);
    XCTAssertEqualObjects([inspection.stagedPolicy.rows valueForKey:@"subject"],
                          (@[@"Any server", @"search.example.com"]));
    XCTAssertEqualObjects(inspection.stagedPolicy.rows[1].purpose,
                          @"Podcast directory search, only when you type in Search.");
    XCTAssertEqual(inspection.stagedPolicy.warnings.count, 2u);

    // Both branches of the user's setting, on this real inspection.
    XCTAssertEqual([CDRNetworkGate decisionForInspection:inspection preferences:GatePreferences(YES)],
                   CDRNetworkGateDecisionNoAsk);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:inspection preferences:GatePreferences(NO)],
                   CDRNetworkGateDecisionAskWithPolicy);

    // Approved: the ordinary swap.
    XCTAssertNil(d.finishError, @"%@", d.finishError);
    XCTAssertEqualObjects([self installedVersion], @"1.2");
    XCTAssertTrue([self stagingIsGone]);
}

- (void)testBuildThatGainsAccessWithoutAPolicyIsDiscardedWhenDeclined {
    if (![self networkGateArtifactsAreUsable]) { XCTSkip(@"needs build-testee.sh --notarize (v1.3)"); }
    [self pointInstalledAppAtManifest:@"manifest-1.3.json"];

    CDRInspectingDelegate *d = [self runInspectingOperationWithManifest:[self manifestNamed:@"manifest-1.3.json"]
                                                                 answer:CDRInspectAnswerDecline];

    XCTAssertEqual(d.inspection.change, CDRNetworkChangeGained);
    XCTAssertFalse(d.inspection.hasPolicy);
    XCTAssertNil(d.inspection.stagedPolicy);
    // No policy: asked whichever way the exemption is set.
    XCTAssertEqual([CDRNetworkGate decisionForInspection:d.inspection preferences:GatePreferences(YES)],
                   CDRNetworkGateDecisionAskWithoutPolicy);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:d.inspection preferences:GatePreferences(NO)],
                   CDRNetworkGateDecisionAskWithoutPolicy);

    // Declined: staging discarded like any failure; nothing else happened.
    XCTAssertEqual(d.finishError.code, CDRErrorApprovalDeclined);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseSwapping]);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseAwaitingQuit]);
    XCTAssertEqualObjects([self installedVersion], @"1.0", @"installed app untouched");
    XCTAssertTrue([self stagingIsGone]);
}

- (void)testParkedApprovalHoldsTheVerifiedBuildAndCancellingDiscardsIt {
    if (![self networkGateArtifactsAreUsable]) { XCTSkip(@"needs build-testee.sh --notarize (v1.3)"); }
    [self pointInstalledAppAtManifest:@"manifest-1.3.json"];

    CDRInspectingDelegate *delegate = [[CDRInspectingDelegate alloc] init];
    delegate.answer = CDRInspectAnswerHold;
    delegate.inspected = [self expectationWithDescription:@"inspected"];
    delegate.finished = [self expectationWithDescription:@"operation finished"];
    CDRUpdateOperation *op = [[CDRUpdateOperation alloc] initWithRegistration:[self registration]
                                                                     manifest:[self manifestNamed:@"manifest-1.3.json"]
                                                                      session:self.session
                                                                     delegate:delegate];
    [op start];
    [self waitForExpectations:@[delegate.inspected] timeout:120];

    // Parked: verified and staged, and going nowhere on its own.
    XCTAssertTrue(op.isParkedForApproval);
    XCTAssertEqual(op.phase, CDRUpdatePhaseInspecting);
    XCTAssertFalse([self stagingIsGone], @"the verified build is held in staging");
    XCTAssertEqualObjects([self installedVersion], @"1.0");
    XCTestExpectation *stillParked = [self expectationWithDescription:@"still parked"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [stillParked fulfill];
    });
    [self waitForExpectations:@[stillParked] timeout:5];
    XCTAssertTrue(op.isParkedForApproval);
    XCTAssertFalse([delegate sawPhase:CDRUpdatePhaseSwapping]);
    XCTAssertEqualObjects([self installedVersion], @"1.0");

    // Discarded from outside (the app quitting, the update superseded).
    [op cancelParkedApproval];
    [self waitForExpectations:@[delegate.finished] timeout:30];
    XCTAssertEqual(delegate.finishError.code, CDRErrorApprovalDeclined);
    XCTAssertTrue([self stagingIsGone]);
    XCTAssertEqualObjects([self installedVersion], @"1.0");

    // A late answer to a discarded approval does nothing.
    delegate.heldReply(YES);
    XCTestExpectation *settled = [self expectationWithDescription:@"settled"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [settled fulfill];
    });
    [self waitForExpectations:@[settled] timeout:5];
    XCTAssertEqualObjects([self installedVersion], @"1.0");
    XCTAssertFalse([delegate sawPhase:CDRUpdatePhaseSwapping]);
}

- (void)testBuildThatDropsNetworkAccessIsReportedAsGoodNewsAndNeverAskedAbout {
    if (![self networkGateArtifactsAreUsable]) { XCTSkip(@"needs build-testee.sh --notarize (v0.9)"); }
    // Start from the unsandboxed 0.9; 1.1 is sandboxed with no network.
    [[NSFileManager defaultManager] removeItemAtURL:self.installedApp error:NULL];
    NSTask *copy = [[NSTask alloc] init];
    copy.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    copy.arguments = @[[self.serveDir URLByAppendingPathComponent:@"ConductorTestee-0.9.app"].path, self.installedApp.path];
    [copy launchAndReturnError:NULL];
    [copy waitUntilExit];
    XCTAssertEqualObjects([self installedVersion], @"0.9");

    CDRInspectingDelegate *d = [self runInspectingOperationWithManifest:[self manifestNamed:@"manifest.json"]
                                                                 answer:CDRInspectAnswerApprove];
    XCTAssertEqual(d.inspection.installedPosture, CDRNetworkPostureUnrestricted);
    XCTAssertEqual(d.inspection.stagedPosture, CDRNetworkPostureNone);
    XCTAssertEqual(d.inspection.change, CDRNetworkChangeLost);
    XCTAssertEqualObjects(d.inspection.addedEntitlements, (@[CDREntitlementAppSandbox]));
    XCTAssertEqual([CDRNetworkGate decisionForInspection:d.inspection preferences:GatePreferences(NO)],
                   CDRNetworkGateDecisionNoAsk);
    XCTAssertNil(d.finishError, @"%@", d.finishError);
    XCTAssertEqualObjects([self installedVersion], @"1.1");
}

- (void)testOrdinaryUpdateInspectsAsNoChange {
    if (![self networkGateArtifactsAreUsable]) { XCTSkip(@"needs build-testee.sh --notarize"); }
    CDRInspectingDelegate *d = [self runInspectingOperationWithManifest:[self manifestNamed:@"manifest.json"]
                                                                 answer:CDRInspectAnswerApprove];
    XCTAssertEqual(d.inspection.installedPosture, CDRNetworkPostureNone);
    XCTAssertEqual(d.inspection.stagedPosture, CDRNetworkPostureNone);
    XCTAssertEqual(d.inspection.change, CDRNetworkChangeNone);
    XCTAssertEqual(d.inspection.addedEntitlements.count, 0u);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:d.inspection preferences:GatePreferences(NO)],
                   CDRNetworkGateDecisionNoAsk);
    XCTAssertNil(d.finishError, @"%@", d.finishError);
    XCTAssertEqualObjects([self installedVersion], @"1.1");
}

- (void)testInspectNeverRunsOnABuildThatFailedVerify {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }
    // The ad-hoc build carries whatever entitlements an attacker likes. It
    // must be refused by Verify before anything reads them.
    [self pointInstalledAppAtManifest:@"manifest-adhoc.json"];
    CDRInspectingDelegate *d = [self runInspectingOperationWithManifest:[self manifestNamed:@"manifest-adhoc.json"]
                                                                 answer:CDRInspectAnswerApprove];
    XCTAssertTrue(d.finishError.code == CDRErrorTeamIDMismatch || d.finishError.code == CDRErrorSignatureInvalid,
                  @"got %@", d.finishError);
    XCTAssertEqual(d.inspectCount, 0u, @"the delegate was never asked");
    XCTAssertNil(d.inspection);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseInspecting]);
    XCTAssertEqualObjects([self installedVersion], @"1.0");
    XCTAssertTrue([self stagingIsGone]);
}

- (void)testInspectNeverRunsOnAReplayedOlderBuild {
    if (!self.serveDir) { XCTSkip(@"run TestHarness/build-testee.sh first"); }
    [self pointInstalledAppAtManifest:@"manifest-replay.json"];
    CDRInspectingDelegate *d = [self runInspectingOperationWithManifest:[self manifestNamed:@"manifest-replay.json"]
                                                                 answer:CDRInspectAnswerApprove];
    XCTAssertEqual(d.finishError.code, CDRErrorNotAnUpgrade);
    XCTAssertEqual(d.inspectCount, 0u);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseInspecting]);
}

@end
