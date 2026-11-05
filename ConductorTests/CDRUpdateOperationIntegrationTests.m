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

@end
