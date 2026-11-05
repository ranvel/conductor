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
@end

/// A scanner that "finds" the fixture bundles instead of /Applications.
@interface CDRFixtureScanner : CDRAppScanner
@property (nonatomic, copy) NSArray<CDRAppRegistration *> *fixtures;
@end

@implementation CDRFixtureScanner
- (NSArray<CDRAppRegistration *> *)scanApplicationsDirectory { return self.fixtures ?: @[]; }
@end

/// Records what the controller asks to be shown; presents nothing.
@interface CDRRecordingPresenter : NSObject <CDRUpdatePresenting>
@property (nonatomic) NSMutableArray<NSString *> *events;
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
- (void)presentRetractionNotice:(NSString *)message vendorURL:(NSURL *)vendorURL {
    [self.events addObject:@"presentRetractionNotice"];
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
    self.controller = [[CDRUpdateController alloc] initWithSession:session
                                                           scanner:scanner
                                                           fetcher:[[CDRManifestFetcher alloc] initWithSession:session]
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

@end
