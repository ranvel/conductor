//
//  CDRUpdateControllerPolicyTests.m
//  ConductorTests
//
//  The controller's side of CND-5: decisions use the *app's* resolved
//  preferences, a preference change re-decides without fetching or
//  notifying, and the two pane actions ("Always allow for this app",
//  "Update now") do what they say. Nothing here starts an update operation
//  or touches the network: manifests are handed to the controller directly.
//

#import <XCTest/XCTest.h>
#import "CDRAppRegistration.h"
#import "CDRAppScanner.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRUpdateController.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdatePreferences.h"
#import "CDRUpdatePresenting.h"
#import "CDRUpdateStateStore.h"
#import "CDRAppUpdateState.h"

static NSString * const kAppBundleID = @"com.example.policy-app";

/// Test-only view of the controller's decision entry point.
@interface CDRUpdateController (PolicyTesting)
- (CDRUpdateDecision *)evaluateManifest:(CDRManifest *)manifest
                           registration:(CDRAppRegistration *)reg
                           breakThrough:(BOOL)breakThrough
                                 notify:(BOOL)notify;
- (CDRUpdateDecision *)evaluateManifest:(CDRManifest *)manifest
                           registration:(CDRAppRegistration *)reg
                           breakThrough:(BOOL)breakThrough
                            userStarted:(BOOL)userStarted
                                 notify:(BOOL)notify;
@end

/// A scanner that "finds" the fixture bundles instead of /Applications.
@interface CDRFixtureScanner : CDRAppScanner
@property (nonatomic, copy) NSArray<CDRAppRegistration *> *fixtures;
@end

@implementation CDRFixtureScanner
- (NSArray<CDRAppRegistration *> *)scanApplicationsDirectory { return self.fixtures ?: @[]; }
@end

/// A fetcher that "serves" one canned manifest (or error) with no network.
@interface CDRFixtureFetcher : CDRManifestFetcher
@property (nonatomic, nullable) CDRManifest *manifest;
@property (nonatomic) NSUInteger fetchCount;
@end

@implementation CDRFixtureFetcher
- (void)fetchManifestForRegistration:(CDRAppRegistration *)registration
                          completion:(void (^)(CDRManifest *, NSError *))completion {
    self.fetchCount++;
    completion(self.manifest, self.manifest ? nil : [NSError errorWithDomain:NSURLErrorDomain code:-1009 userInfo:nil]);
}
@end

/// Records what the controller asks to be shown; presents nothing.
@interface CDRRecordingPresenter : NSObject <CDRUpdatePresenting>
@property (nonatomic) NSMutableArray<NSString *> *events;
/// What the stand-in "user" answers on the held sheet / retraction sheet.
@property (nonatomic) BOOL confirmsHeldInstall;
@property (nonatomic) BOOL acknowledgesRetraction;
@end

@implementation CDRRecordingPresenter
- (instancetype)init {
    self = [super init];
    _events = [NSMutableArray array];
    return self;
}
- (void)presentQuitDecisionForAppNamed:(NSString *)appName reply:(void (^)(CDRQuitDecision))reply {
    [self.events addObject:@"presentQuitDecision"];
    reply(CDRQuitDecisionSkip);
}
- (void)presentDeferredOfferForAppNamed:(NSString *)appName version:(NSString *)version
                          deferredUntil:(NSDate *)deferredUntil completion:(void (^)(BOOL))completion {
    [self.events addObject:@"presentDeferredOffer"];
    completion(NO);
}
- (void)presentRetractionForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID appURL:(NSURL *)appURL
                    retractedVersion:(NSString *)retractedVersion installedVersion:(NSString *)installedVersion
                             message:(NSString *)message vendorURL:(NSURL *)vendorURL
                          completion:(void (^)(BOOL))completion {
    [self.events addObject:[NSString stringWithFormat:@"presentRetraction %@ (installed %@)",
                            retractedVersion, installedVersion]];
    completion(self.acknowledgesRetraction);
}
- (void)presentHeldUpdateForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID appURL:(NSURL *)appURL
                             version:(NSString *)version heldGroups:(NSArray<CDRReleaseNoteGroup *> *)heldGroups
                           holdTypes:(CDRReleaseNoteTypeSet)holdTypes completion:(void (^)(BOOL))completion {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (CDRReleaseNoteGroup *group in heldGroups) {
        for (CDRReleaseNote *note in group.notes) [texts addObject:note.text];
    }
    [self.events addObject:[NSString stringWithFormat:@"presentHeld %@ [%@] holds %@", version,
                            [texts componentsJoinedByString:@" | "], CDRReleaseNoteTypeSetDisplayList(holdTypes)]];
    completion(self.confirmsHeldInstall);
}
- (void)presentNetworkApprovalForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID appURL:(NSURL *)appURL
                              fromVersion:(NSString *)fromVersion toVersion:(NSString *)toVersion
                                diffLines:(NSArray<CDRInterruptSheetDiffLine *> *)diffLines
                               policyRows:(NSArray<CDRInterruptSheetPolicyRow *> *)policyRows
                               completion:(void (^)(CDRInterruptSheetAction))completion {
    [self.events addObject:@"presentNetworkApproval"];
    completion(CDRInterruptSheetActionDismiss);
}
- (void)presentRelaunchOfferForAppNamed:(NSString *)appName appURL:(NSURL *)appURL {
    [self.events addObject:@"presentRelaunchOffer"];
}
- (void)notifyUpdateAvailableForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID
                                 version:(NSString *)version urgency:(CDRUrgency)urgency {
    [self.events addObject:[@"available " stringByAppendingString:version]];
}
- (void)notifyUpdateNeedsAttentionForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID
                                      version:(NSString *)version reason:(NSString *)reason {
    [self.events addObject:[NSString stringWithFormat:@"attention %@: %@", version, reason]];
}
- (void)notifyRetractedPending:(NSString *)message bundleID:(NSString *)bundleID vendorURL:(NSURL *)vendorURL {
    [self.events addObject:@"retractedPending"];
}
- (void)notifyRetractedInstalled:(NSString *)message bundleID:(NSString *)bundleID vendorURL:(NSURL *)vendorURL {
    [self.events addObject:@"retractedInstalled"];
}
- (void)notifyInstallCompletedForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID version:(NSString *)version {
    [self.events addObject:@"installCompleted"];
}
- (void)notifyInstallFailedForAppNamed:(NSString *)appName bundleID:(NSString *)bundleID
                                 error:(NSError *)error vendorURL:(NSURL *)vendorURL {
    [self.events addObject:@"installFailed"];
}
@end

@interface CDRUpdateControllerPolicyTests : XCTestCase
@property (nonatomic) NSURL *root;
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic, copy) NSString *suiteName;
@property (nonatomic) CDRUpdateStateStore *store;
@property (nonatomic) CDRRecordingPresenter *presenter;
@property (nonatomic) CDRUpdateController *controller;
@property (nonatomic) CDRAppRegistration *registration;
@property (nonatomic) CDRFixtureFetcher *fetcher;
@end

@implementation CDRUpdateControllerPolicyTests

- (void)setUp {
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-controller-policy-%@", NSUUID.UUID.UUIDString]
                        isDirectory:YES];
    self.suiteName = [NSString stringWithFormat:@"cdr-controller-policy-%@", NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
    self.store = [[CDRUpdateStateStore alloc]
        initWithDirectoryURL:[self.root URLByAppendingPathComponent:@"state" isDirectory:YES] now:[NSDate date]];
    self.presenter = [[CDRRecordingPresenter alloc] init];
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:self.suiteName];
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
}

/// Builds the controller around one fixture app at `installed`.
- (void)startWithInstalledVersion:(NSString *)installed {
    NSURL *appURL = [self.root URLByAppendingPathComponent:@"Applications/PolicyApp.app"];
    NSURL *resources = [appURL URLByAppendingPathComponent:@"Contents/Resources"];
    [[NSFileManager defaultManager] createDirectoryAtURL:resources withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    [@{@"CFBundleIdentifier": kAppBundleID, @"CFBundleShortVersionString": installed}
        writeToURL:[appURL URLByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    [[NSJSONSerialization dataWithJSONObject:@{@"conductor": @1, @"update_url": @"https://example.com/manifest.json"}
                                     options:0 error:NULL]
        writeToURL:[resources URLByAppendingPathComponent:@"conductor.json"] atomically:YES];
    self.registration = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    XCTAssertNotNil(self.registration);

    CDRDevModeSession *session = [CDRDevModeSession sessionFromArguments:@[@"conductor"] error:NULL];
    CDRFixtureScanner *scanner = [[CDRFixtureScanner alloc] init];
    scanner.fixtures = @[self.registration];
    self.fetcher = [[CDRFixtureFetcher alloc] initWithSession:session];
    self.controller = [[CDRUpdateController alloc] initWithSession:session
                                                           scanner:scanner
                                                           fetcher:self.fetcher
                                                        stateStore:self.store
                                                          defaults:self.defaults];
    self.controller.presenter = self.presenter;
    [self.controller rescan];
    XCTAssertEqual(self.controller.rowModels.count, 1u);
}

- (CDRManifest *)manifest:(NSString *)version notes:(NSArray<NSString *> *)types {
    NSMutableArray *notes = [NSMutableArray array];
    for (NSString *type in types) [notes addObject:@{@"type": type, @"text": [type stringByAppendingString:@" note"]}];
    return [CDRManifest manifestWithData:[NSJSONSerialization dataWithJSONObject:@{
        @"conductor_manifest": @1, @"bundle_id": kAppBundleID, @"version": version,
        @"url": @"https://example.com/app.dmg", @"notes": notes,
    } options:0 error:NULL] error:NULL];
}

- (CDRAppRowModel *)row { return self.controller.rowModels.firstObject; }

- (void)writeGlobal:(void (^)(CDRMutableUpdatePreferences *prefs))change {
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences preferencesFromDefaults:self.defaults] mutableCopy];
    change(prefs);
    [prefs writeToDefaults:self.defaults];
}

#pragma mark - Holds

- (void)testAnUpdateWithARemovalIsHeldAnnouncedWithoutAnInstallAction {
    [self startWithInstalledVersion:@"1.3"];
    [self.controller evaluateManifest:[self manifest:@"1.4" notes:@[@"removed", @"fixed"]]
                         registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];   // rebuild rows

    XCTAssertEqual([self row].state, CDRAppRowStateHeld);
    XCTAssertEqual([self row].section, CDRAppRowSectionNeedsYou);
    XCTAssertTrue([self row].actions & CDRAppRowActionInstall, @"installable — by a deliberate click");
    // The "waiting for you" notice, not the Install-button one.
    XCTAssertEqualObjects(self.presenter.events, (@[@"attention 1.4: Held because it includes a removal."]));
    XCTAssertEqualObjects([self.store stateForBundleID:kAppBundleID].lastNotifiedVersion, @"1.4");
}

- (void)testRemovingTheHoldCategoryReleasesTheHoldWithoutACheckOrANotification {
    [self startWithInstalledVersion:@"1.3"];
    [self.controller evaluateManifest:[self manifest:@"1.4" notes:@[@"removed"]]
                         registration:self.registration breakThrough:NO notify:YES];
    [self.presenter.events removeAllObjects];

    // Globally…
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) {
        prefs.holdTypes = prefs.holdTypes & ~CDRReleaseNoteTypeSetRemoved;
    }];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
    XCTAssertEqual(self.presenter.events.count, 0u, @"a settings change announces nothing");

    // …put it back, and it holds again…
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) {
        prefs.holdTypes = prefs.holdTypes | CDRReleaseNoteTypeSetRemoved;
    }];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateHeld);

    // …or release it for this app only.
    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.holdTypes = @(CDRReleaseNoteTypeSetNotice);
    CDRSetAppPolicyOverride(override, kAppBundleID, self.defaults);
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
    XCTAssertEqual(self.presenter.events.count, 0u);
}

#pragma mark - Major stops

- (void)testAlwaysAllowForThisAppWritesAnOverrideAndTheUpdateProceedsNormally {
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) { prefs.stopAtMajorVersions = YES; }];
    [self startWithInstalledVersion:@"0.9"];
    [self.controller evaluateManifest:[self manifest:@"1.0" notes:@[@"added"]]
                         registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateStoppedAtMajor);
    XCTAssertTrue([self row].actions & CDRAppRowActionAlwaysAllowMajor);
    XCTAssertEqual(self.presenter.events.count, 1u);
    XCTAssertTrue([self.presenter.events.firstObject hasPrefix:@"attention 1.0: 1.0 is a major version"]);

    [self.controller performRowAction:CDRAppRowActionAlwaysAllowMajor forBundleID:kAppBundleID];

    XCTAssertEqualObjects(CDRAppPolicyOverrideForBundleID(kAppBundleID, self.defaults).stopAtMajorVersions, @NO);
    XCTAssertTrue([CDRUpdatePreferences preferencesFromDefaults:self.defaults].stopAtMajorVersions,
                  @"Settings itself still stops at major versions");
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
    XCTAssertFalse([self row].actions & CDRAppRowActionAlwaysAllowMajor);
    XCTAssertEqual(self.presenter.events.count, 1u, @"nothing new is announced");
}

- (void)testAMinorBumpIsNotStopped {
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) { prefs.stopAtMajorVersions = YES; }];
    [self startWithInstalledVersion:@"1.9"];
    [self.controller evaluateManifest:[self manifest:@"1.10" notes:@[@"added"]]
                         registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
    XCTAssertEqualObjects(self.presenter.events, (@[@"available 1.10"]));
}

#pragma mark - Per-app deferral

- (void)testAPerAppDeferralHoldsOneAppWhileSettingsIsOff {
    [self startWithInstalledVersion:@"1.0"];
    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.soakDuration = @(CDRSoakDurationOneWeek);
    CDRSetAppPolicyOverride(override, kAppBundleID, self.defaults);
    XCTAssertEqual([CDRUpdatePreferences preferencesFromDefaults:self.defaults].soakDuration, CDRSoakDurationOff);

    CDRUpdateDecision *d = [self.controller evaluateManifest:[self manifest:@"1.1" notes:@[@"fixed"]]
                                                registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertEqual([self row].state, CDRAppRowStateDeferred);
    XCTAssertEqualObjects([self row].deferralDurationName, @"1 week");
    XCTAssertEqual(self.presenter.events.count, 0u, @"a deferred update is hidden: nothing is announced");
    XCTAssertNil([self.store stateForBundleID:kAppBundleID].lastNotifiedVersion);

    // A deliberate per-app check still breaks through (the offer is modal
    // and user-started; the recording presenter declines it).
    d = [self.controller evaluateManifest:[self manifest:@"1.1" notes:@[@"fixed"]]
                             registration:self.registration breakThrough:YES notify:YES];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferredOffered);
    XCTAssertEqualObjects(self.presenter.events, (@[@"presentDeferredOffer"]));

    // Dropping the override follows Settings (Off) again: surfaced at once.
    CDRSetAppPolicyOverride(nil, kAppBundleID, self.defaults);
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
}

- (void)testUpdateNowOnADeferredUpdateIsConsentAndThenMeetsTheUsersGates {
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) { prefs.soakDuration = CDRSoakDurationThreeDays; }];
    [self startWithInstalledVersion:@"1.3"];
    // A deferred update that also contains a removal.
    [self.controller evaluateManifest:[self manifest:@"1.4" notes:@[@"removed"]]
                         registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateDeferred);
    XCTAssertTrue([self row].actions & CDRAppRowActionInstallDeferred);
    XCTAssertFalse([self row].actions & CDRAppRowActionInstall);

    [self.controller performRowAction:CDRAppRowActionInstallDeferred forBundleID:kAppBundleID];

    // Consent marks it notified (retraction loudness applies from here)…
    XCTAssertEqualObjects([self.store stateForBundleID:kAppBundleID].lastNotifiedVersion, @"1.4");
    // …and the update is now surfaced — where the hold applies. It did not
    // install on that one click, and no modal was raised.
    XCTAssertEqual([self row].state, CDRAppRowStateHeld);
    XCTAssertEqual(self.presenter.events.count, 0u);
}

- (void)testUrgencyBypassesDeferralButStillLandsInHeld {
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) { prefs.soakDuration = CDRSoakDurationOneWeek; }];
    [self startWithInstalledVersion:@"1.3"];
    CDRManifest *urgent = [CDRManifest manifestWithData:[NSJSONSerialization dataWithJSONObject:@{
        @"conductor_manifest": @1, @"bundle_id": kAppBundleID, @"version": @"1.4",
        @"url": @"https://example.com/app.dmg", @"urgency": @"data_loss",
        @"notes": @[@{@"type": @"removed", @"text": @"gone"}],
    } options:0 error:NULL] error:NULL];
    [self.controller evaluateManifest:urgent registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateHeld);
    XCTAssertEqual([self row].urgency, CDRUrgencyDataLoss);
}

#pragma mark - What a preference change must not disturb

- (void)testAPreferenceChangeDoesNotEraseAnUnreadRetractionNotice {
    [self startWithInstalledVersion:@"1.0"];
    [self.controller evaluateManifest:[self manifest:@"1.1" notes:@[@"fixed"]]
                         registration:self.registration breakThrough:NO notify:YES];
    // The developer pulls 1.1.
    [self.controller evaluateManifest:[self manifest:@"1.0" notes:@[]]
                         registration:self.registration breakThrough:NO notify:YES];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateRetracted);

    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) { prefs.stopAtMajorVersions = YES; }];
    [self.controller preferencesDidChange];
    XCTAssertEqual([self row].state, CDRAppRowStateRetracted, @"the notice stays until it is acknowledged");
}

#pragma mark - Interrupt sheets (CND-6)

/// Runs a real check through the fixture fetcher and waits for the decision.
- (void)check:(CDRManifest *)manifest userStarted:(BOOL)userStarted {
    self.fetcher.manifest = manifest;
    NSUInteger before = self.fetcher.fetchCount;
    if (userStarted) [self.controller checkAllUserStarted];
    else [self.controller checkAllPassive];
    XCTAssertEqual(self.fetcher.fetchCount, before + 1);
    [self spinMainQueue];
}

/// Lets blocks already queued on the main queue run (the controller hops
/// there to decide).
- (void)spinMainQueue {
    XCTestExpectation *drained = [self expectationWithDescription:@"main queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:5];
}

- (void)testInstallOnAHeldRowOpensTheHeldSheetInsteadOfInstalling {
    [self startWithInstalledVersion:@"1.3"];
    [self check:[self manifest:@"1.4" notes:@[@"fixed", @"removed"]] userStarted:NO];
    XCTAssertEqual([self row].state, CDRAppRowStateHeld);
    [self.presenter.events removeAllObjects];

    // "Not now" on the sheet.
    self.presenter.confirmsHeldInstall = NO;
    [self.controller performRowAction:CDRAppRowActionInstall forBundleID:kAppBundleID];
    [self spinMainQueue];
    // The sheet was asked for, with only the offending note and the user's
    // hold categories…
    XCTAssertEqualObjects(self.presenter.events,
                          (@[@"presentHeld 1.4 [removed note] holds Notice, Removed, Retracted"]));
    // …and nothing was installed: the row is still Held.
    XCTAssertEqual([self row].state, CDRAppRowStateHeld);
    XCTAssertFalse(self.controller.hasOperationsInCriticalPhase);
}

- (void)testInstallFromTheHeldSheetProceedsThroughTheNormalInstallPath {
    [self startWithInstalledVersion:@"1.3"];
    [self check:[self manifest:@"1.4" notes:@[@"removed"]] userStarted:NO];
    [self.presenter.events removeAllObjects];

    self.presenter.confirmsHeldInstall = YES;
    [self.controller performRowAction:CDRAppRowActionInstall forBundleID:kAppBundleID];

    // The ordinary pipeline runs — and, as for any install, refuses the
    // unsigned fixture app at its very first step, before any network.
    XCTestExpectation *finished = [self expectationWithDescription:@"operation finished"];
    __block BOOL fulfilled = NO;
    self.controller.onRowModelsChanged = ^{
        if (!fulfilled && [self.presenter.events containsObject:@"installFailed"]) {
            fulfilled = YES;
            [finished fulfill];
        }
    };
    [self waitForExpectations:@[finished] timeout:15];
    XCTAssertEqualObjects(self.presenter.events.firstObject, @"presentHeld 1.4 [removed note] holds Notice, Removed, Retracted");
    XCTAssertEqualObjects([self.store stateForBundleID:kAppBundleID].lastNotifiedVersion, @"1.4");
}

- (void)testAStoppedUpdateThatIsAlsoHeldGoesThroughTheHeldSheetToo {
    [self writeGlobal:^(CDRMutableUpdatePreferences *prefs) { prefs.stopAtMajorVersions = YES; }];
    [self startWithInstalledVersion:@"0.9"];
    [self check:[self manifest:@"1.0" notes:@[@"notice"]] userStarted:NO];
    XCTAssertEqual([self row].state, CDRAppRowStateStoppedAtMajor);
    [self.presenter.events removeAllObjects];

    [self.controller performRowAction:CDRAppRowActionInstall forBundleID:kAppBundleID];
    XCTAssertEqualObjects(self.presenter.events,
                          (@[@"presentHeld 1.0 [notice note] holds Notice, Removed, Retracted"]));
    XCTAssertEqual([self row].state, CDRAppRowStateStoppedAtMajor);
}

- (void)testAnOrdinaryUpdateNeverShowsTheHeldSheet {
    [self startWithInstalledVersion:@"1.3"];
    [self check:[self manifest:@"1.4" notes:@[@"fixed"]] userStarted:NO];
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
    XCTAssertEqualObjects(self.presenter.events, (@[@"available 1.4"]));
}

- (void)testARetractionFoundByAScheduledCheckIsNotifiedAndItsBannerPersists {
    [self startWithInstalledVersion:@"1.1"];
    [self check:[self manifest:@"1.2" notes:@[@"fixed"]] userStarted:NO];
    XCTAssertEqualObjects(self.presenter.events, (@[@"available 1.2"]));

    // The developer pulls 1.2. A scheduled check finds out: passive only.
    [self check:[self manifest:@"1.1" notes:@[]] userStarted:NO];
    XCTAssertEqualObjects(self.presenter.events, (@[@"available 1.2", @"retractedPending"]));
    XCTAssertEqual([self row].state, CDRAppRowStateRetracted);
    XCTAssertEqualObjects([self row].retractedVersion, @"1.2");
    XCTAssertNotNil([self row].retractionAdvertisedDate);
    XCTAssertNotNil([self row].retractionPulledDate);

    // Later checks decide "up to date" — the policy's memory was one-time —
    // but the unread notice keeps the row's banner, and nothing is re-announced.
    [self check:[self manifest:@"1.1" notes:@[]] userStarted:NO];
    [self check:[self manifest:@"1.1" notes:@[]] userStarted:YES];
    XCTAssertEqual(self.presenter.events.count, 2u);
    XCTAssertEqual([self row].state, CDRAppRowStateRetracted);
    XCTAssertEqual([self row].section, CDRAppRowSectionNeedsYou);

    // It survives a relaunch: a new controller over the same defaults.
    CDRUpdateController *relaunched = [[CDRUpdateController alloc]
        initWithSession:[CDRDevModeSession sessionFromArguments:@[@"conductor"] error:NULL]
                scanner:({ CDRFixtureScanner *scanner = [[CDRFixtureScanner alloc] init];
                           scanner.fixtures = @[self.registration]; scanner; })
                fetcher:self.fetcher stateStore:self.store defaults:self.defaults];
    [relaunched rescan];
    XCTAssertEqual(relaunched.rowModels.firstObject.state, CDRAppRowStateRetracted);

    // "Got it" clears it; the row is plainly up to date.
    [self.controller performRowAction:CDRAppRowActionAcknowledge forBundleID:kAppBundleID];
    [self spinMainQueue];
    XCTAssertEqual([self row].state, CDRAppRowStateUpToDate);
    XCTAssertNil([self.defaults objectForKey:@"CDRRetractionNotices"]);
}

- (void)testARetractionFoundByACheckTheUserStartedIsPresented {
    [self startWithInstalledVersion:@"1.1"];
    [self check:[self manifest:@"1.2" notes:@[@"fixed"]] userStarted:NO];
    [self.presenter.events removeAllObjects];

    // The user presses Check now; the presenter decides sheet vs notice.
    self.presenter.acknowledgesRetraction = YES;   // they read the sheet and pressed OK
    [self check:[self manifest:@"1.1" notes:@[]] userStarted:YES];
    [self spinMainQueue];
    XCTAssertEqualObjects(self.presenter.events.firstObject, @"presentRetraction 1.2 (installed 1.1)");
    XCTAssertFalse([self.presenter.events containsObject:@"retractedPending"]);
    // Acknowledged on the sheet: no banner left behind.
    XCTAssertEqual([self row].state, CDRAppRowStateUpToDate);
}

- (void)testAnUnacknowledgedSheetLeavesTheBanner {
    [self startWithInstalledVersion:@"1.1"];
    [self check:[self manifest:@"1.2" notes:@[@"fixed"]] userStarted:NO];
    self.presenter.acknowledgesRetraction = NO;    // window wasn't key: it fell back to the notice
    [self check:[self manifest:@"1.1" notes:@[]] userStarted:YES];
    XCTAssertEqual([self row].state, CDRAppRowStateRetracted);
}

- (void)testANewerVersionMakesAnOldRetractionNoticeMoot {
    [self startWithInstalledVersion:@"1.1"];
    [self check:[self manifest:@"1.2" notes:@[@"fixed"]] userStarted:NO];
    [self check:[self manifest:@"1.1" notes:@[]] userStarted:NO];
    XCTAssertEqual([self row].state, CDRAppRowStateRetracted);

    [self check:[self manifest:@"1.3" notes:@[@"fixed"]] userStarted:NO];
    XCTAssertEqual([self row].state, CDRAppRowStateAvailable);
    XCTAssertNil([self.defaults objectForKey:@"CDRRetractionNotices"]);
}

@end
