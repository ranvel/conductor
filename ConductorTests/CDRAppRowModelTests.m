//
//  CDRAppRowModelTests.m
//  ConductorTests
//
//  The row model is the single mapping both UI surfaces render from; these
//  tests pin every outcome → (state, stateLine, actions, badge) so the menu
//  and the window cannot drift, and guard the copy rule that user-facing text
//  never says "soak".
//

#import <XCTest/XCTest.h>
#import "CDRAppRowModel.h"
#import "CDRAppRegistration.h"
#import "CDRAppUpdateState.h"
#import "CDRManifest.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdatePreferences.h"
#import "CDRRetractionNotices.h"
#import "CDRErrors.h"

static NSString * const kBundleID = @"com.example.app";

/// Preferences for a state-table row: the given deferral, no hold categories
/// (beyond the always-on Retracted) and no major stop — so a row written
/// about deferral or retraction is not also a statement about v2's gates.
static CDRUpdatePreferences *PrefsWithSoak(CDRSoakDuration soak) {
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    prefs.soakDuration = soak;
    prefs.holdTypes = CDRReleaseNoteTypeSetNone;
    return [prefs copy];
}

@interface CDRAppRowModelTests : XCTestCase
@property (nonatomic) NSURL *fixtureRoot;
@property (nonatomic) NSDate *now;
@end

@implementation CDRAppRowModelTests

- (void)setUp {
    [super setUp];
    self.fixtureRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-rowmodel-tests-%@", NSUUID.UUID.UUIDString]
                        isDirectory:YES];
    self.now = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.fixtureRoot error:NULL];
    [super tearDown];
}

#pragma mark - Fixtures

- (CDRAppRegistration *)registrationWithInstalledVersion:(NSString *)version {
    NSURL *appURL = [[self.fixtureRoot URLByAppendingPathComponent:NSUUID.UUID.UUIDString]
        URLByAppendingPathComponent:@"TestApp.app"];
    NSURL *resources = [appURL URLByAppendingPathComponent:@"Contents/Resources"];
    [[NSFileManager defaultManager] createDirectoryAtURL:resources
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [@{
        @"CFBundleIdentifier": kBundleID,
        @"CFBundleShortVersionString": version,
    } writeToURL:[appURL URLByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{
        @"conductor": @1,
        @"update_url": @"https://example.com/manifest.json",
        @"vendor_url": @"https://example.com",
    } options:0 error:NULL];
    [json writeToURL:[resources URLByAppendingPathComponent:@"conductor.json"] atomically:YES];

    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
    XCTAssertNotNil(reg);
    return reg;
}

static CDRManifest *ManifestWithVersion(NSString *version, NSString *urgencyToken) {
    NSMutableDictionary *dict = [@{
        @"conductor_manifest": @1,
        @"bundle_id": kBundleID,
        @"version": version,
        @"url": @"https://example.com/app.dmg",
    } mutableCopy];
    if (urgencyToken) dict[@"urgency"] = urgencyToken;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    return [CDRManifest manifestWithData:data error:NULL];
}

/// Shorthand: decision from the real policy so fixtures can't invent
/// unreachable outcomes.
- (CDRUpdateDecision *)decideInstalled:(NSString *)installed
                              manifest:(CDRManifest *)manifest
                                 state:(CDRAppUpdateState *)state
                                  soak:(CDRSoakDuration)soak
                          breakThrough:(BOOL)breakThrough {
    return [CDRUpdatePolicy decisionForRegistration:[self registrationWithInstalledVersion:installed]
                                           manifest:manifest
                                              state:state
                                       preferences:PrefsWithSoak(soak)
                                       breakThrough:breakThrough
                                                now:self.now];
}

- (CDRAppRowModel *)modelWithInstalled:(NSString *)installed
                              decision:(CDRUpdateDecision *)decision
                              manifest:(CDRManifest *)manifest {
    return [CDRAppRowModel modelForRegistration:[self registrationWithInstalledVersion:installed]
                                   lastDecision:decision
                                decidedManifest:manifest
                                      lastError:nil
                                        ignored:NO
                                 operationPhase:CDRUpdatePhaseIdle
                                         parked:NO];
}

#pragma mark - Outcome mappings

- (void)testAvailableRow {
    CDRManifest *m = ManifestWithVersion(@"1.1", nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil
                                            soak:CDRSoakDurationOff breakThrough:NO];
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];
    XCTAssertEqual(row.state, CDRAppRowStateAvailable);
    XCTAssertTrue([row.stateLine containsString:@"1.1 available"]);
    XCTAssertTrue(row.actions & CDRAppRowActionInstall);
    XCTAssertTrue(row.actions & CDRAppRowActionCheckNow);
    XCTAssertTrue(row.actions & CDRAppRowActionIgnore);
    XCTAssertTrue(row.contributesToBadge);
    XCTAssertEqualObjects(row.availableVersion, @"1.1");
}

- (void)testAvailableUrgentRowAttributesTheFlagToTheDeveloper {
    CDRManifest *m = ManifestWithVersion(@"1.1", @"data_loss");
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil
                                            soak:CDRSoakDurationOff breakThrough:NO];
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];
    XCTAssertTrue([row.stateLine containsString:@"developer"]);
}

- (void)testDeferredRowHidesInstall {
    CDRManifest *m = ManifestWithVersion(@"1.1", nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil
                                            soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];
    XCTAssertEqual(row.state, CDRAppRowStateDeferred);
    XCTAssertTrue([row.stateLine containsString:@"deferred until"]);
    XCTAssertFalse(row.actions & CDRAppRowActionInstall);
    XCTAssertTrue(row.actions & CDRAppRowActionCheckNow);
    XCTAssertFalse(row.contributesToBadge);
}

- (void)testRetractedPendingRowIsCalmButBadges {
    // Notified about 1.1, not installed, manifest back at 1.0 → State A.
    CDRAppUpdateState *state = [[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now]
        stateByNotingNotifiedVersion:@"1.1" build:nil at:self.now];
    CDRManifest *m = ManifestWithVersion(@"1.0", nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:state
                                            soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeRetractedPending);
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];
    XCTAssertTrue([row.stateLine containsString:@"retracted"]);
    XCTAssertFalse(row.actions & CDRAppRowActionInstall);
    XCTAssertTrue(row.actions & CDRAppRowActionVendorSite);
    XCTAssertTrue(row.contributesToBadge);
}

- (void)testRetractedInstalledRowPersistsWithoutBadge {
    // Installed the version that later vanished from the manifest → State B.
    CDRAppUpdateState *state = [[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now]
        stateByNotingNotifiedVersion:@"1.1" build:nil at:self.now];
    CDRManifest *m = ManifestWithVersion(@"1.0", nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.1" manifest:m state:state
                                            soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeRetractedInstalled);
    CDRAppRowModel *row = [self modelWithInstalled:@"1.1" decision:d manifest:m];
    XCTAssertEqual(row.state, CDRAppRowStateRecalled);
    XCTAssertTrue([row.stateLine containsString:@"recalled"]);
    XCTAssertTrue(row.actions & CDRAppRowActionVendorSite);
    XCTAssertFalse(row.contributesToBadge);
}

- (void)testUpToDateAndDroppedSilentlyPresentIdentically {
    CDRManifest *m = ManifestWithVersion(@"1.0", nil);
    CDRUpdateDecision *upToDate = [self decideInstalled:@"1.0" manifest:m state:nil
                                                   soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(upToDate.outcome, CDRUpdateOutcomeUpToDate);

    // Saw 1.1 while deferred (never notified), then it vanished.
    CDRAppUpdateState *soaking = [[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now];
    CDRUpdateDecision *dropped = [self decideInstalled:@"1.0" manifest:m state:soaking
                                                  soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(dropped.outcome, CDRUpdateOutcomeDroppedSilently);

    CDRAppRowModel *a = [self modelWithInstalled:@"1.0" decision:upToDate manifest:m];
    CDRAppRowModel *b = [self modelWithInstalled:@"1.0" decision:dropped manifest:m];
    XCTAssertEqual(a.state, b.state);
    XCTAssertEqualObjects(a.stateLine, b.stateLine);
    XCTAssertEqual(a.actions, b.actions);
    XCTAssertEqual(a.contributesToBadge, b.contributesToBadge);
}

#pragma mark - Precedence

- (void)testIgnoredOverridesDecisionButKeepsCheckNow {
    CDRManifest *m = ManifestWithVersion(@"1.1", nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil
                                            soak:CDRSoakDurationOff breakThrough:NO];
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                  lastDecision:d
                                               decidedManifest:m
                                                     lastError:nil
                                                       ignored:YES
                                                operationPhase:CDRUpdatePhaseIdle
                                                        parked:NO];
    XCTAssertEqual(row.state, CDRAppRowStateIgnored);
    XCTAssertTrue(row.actions & CDRAppRowActionCheckNow);
    XCTAssertTrue(row.actions & CDRAppRowActionUnignore);
    XCTAssertFalse(row.actions & CDRAppRowActionInstall);
    XCTAssertFalse(row.contributesToBadge);
}

- (void)testWorkingRowCarriesPhaseNameAndNoActions {
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                  lastDecision:nil
                                               decidedManifest:nil
                                                     lastError:nil
                                                       ignored:NO
                                                operationPhase:CDRUpdatePhaseDownloading
                                                        parked:NO];
    XCTAssertEqual(row.state, CDRAppRowStateWorking);
    XCTAssertTrue([row.stateLine containsString:CDRUpdatePhaseName(CDRUpdatePhaseDownloading)]);
    XCTAssertEqual(row.actions, CDRAppRowActionNone);
}

- (void)testParkedRowOffersOnlyCancel {
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                  lastDecision:nil
                                               decidedManifest:nil
                                                     lastError:nil
                                                       ignored:NO
                                                operationPhase:CDRUpdatePhaseAwaitingQuit
                                                        parked:YES];
    XCTAssertEqual(row.state, CDRAppRowStateWaitingForQuit);
    XCTAssertTrue([row.stateLine containsString:@"waiting for"]);
    XCTAssertEqual(row.actions, CDRAppRowActionCancelPending);
}

- (void)testCheckFailedRowExposesVendorSiteFromError {
    NSError *error = [NSError errorWithDomain:CDRErrorDomain code:CDRErrorManifestUnreachable
                                     userInfo:@{
        NSLocalizedDescriptionKey: @"could not reach the update server",
        CDRErrorVendorURLKey: [NSURL URLWithString:@"https://vendor.example.com"],
    }];
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                  lastDecision:nil
                                               decidedManifest:nil
                                                     lastError:error
                                                       ignored:NO
                                                operationPhase:CDRUpdatePhaseIdle
                                                        parked:NO];
    XCTAssertEqual(row.state, CDRAppRowStateCheckFailed);
    XCTAssertTrue([row.stateLine containsString:@"check failed"]);
    XCTAssertTrue(row.actions & CDRAppRowActionVendorSite);
    XCTAssertEqualObjects(row.vendorURL.absoluteString, @"https://vendor.example.com");
}

- (void)testUnknownRowBeforeFirstCheck {
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                  lastDecision:nil
                                               decidedManifest:nil
                                                     lastError:nil
                                                       ignored:NO
                                                operationPhase:CDRUpdatePhaseIdle
                                                        parked:NO];
    XCTAssertEqual(row.state, CDRAppRowStateUnknown);
    XCTAssertTrue(row.actions & CDRAppRowActionCheckNow);
    XCTAssertFalse(row.contributesToBadge);
}

#pragma mark - Copy rule

/// "Soak" is spec/internal vocabulary; user-facing copy says "deferred"
/// (deferral.md). The row model is user-facing.
- (void)testNoStateLineEverSaysSoak {
    CDRManifest *newer = ManifestWithVersion(@"1.1", nil);
    CDRManifest *older = ManifestWithVersion(@"1.0", nil);
    CDRAppUpdateState *notified = [[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now]
        stateByNotingNotifiedVersion:@"1.1" build:nil at:self.now];

    NSArray<CDRAppRowModel *> *rows = @[
        [self modelWithInstalled:@"1.0"
                        decision:[self decideInstalled:@"1.0" manifest:newer state:nil
                                                  soak:CDRSoakDurationOff breakThrough:NO]
                        manifest:newer],
        [self modelWithInstalled:@"1.0"
                        decision:[self decideInstalled:@"1.0" manifest:newer state:nil
                                                  soak:CDRSoakDurationOneWeek breakThrough:NO]
                        manifest:newer],
        [self modelWithInstalled:@"1.0"
                        decision:[self decideInstalled:@"1.0" manifest:newer state:nil
                                                  soak:CDRSoakDurationOneWeek breakThrough:YES]
                        manifest:newer],
        [self modelWithInstalled:@"1.0"
                        decision:[self decideInstalled:@"1.0" manifest:older state:notified
                                                  soak:CDRSoakDurationOff breakThrough:NO]
                        manifest:older],
        [self modelWithInstalled:@"1.1"
                        decision:[self decideInstalled:@"1.1" manifest:older state:notified
                                                  soak:CDRSoakDurationOff breakThrough:NO]
                        manifest:older],
        [self modelWithInstalled:@"1.0" decision:nil manifest:nil],
    ];
    for (CDRAppRowModel *row in rows) {
        XCTAssertFalse([row.stateLine.lowercaseString containsString:@"soak"],
                       @"user-facing state line says 'soak': %@", row.stateLine);
    }
}

#pragma mark - Main window fields (CND-3)

static CDRManifest *ManifestWithNotes(NSString *version, NSArray<NSArray<NSString *> *> *notes,
                                      NSArray<NSDictionary *> *history) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray<NSString *> *pair in notes) [items addObject:@{@"type": pair[0], @"text": pair[1]}];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"conductor_manifest": @1,
        @"bundle_id": kBundleID,
        @"version": version,
        @"url": @"https://example.com/app.dmg",
        @"released": @"2026-11-03",
        @"size": @19293798,
        @"changelog_url": @"https://example.com/changelog",
        @"notes": items,
        @"history": history ?: @[],
    } options:0 error:NULL];
    return [CDRManifest manifestWithData:data error:NULL];
}

- (void)testAvailableRowCarriesNotesDotsAndIncludedVersions {
    CDRManifest *m = ManifestWithNotes(@"1.4", @[@[@"fixed", @"f"], @[@"removed", @"r"], @[@"mystery", @"?"]], @[
        @{@"version": @"1.3", @"date": @"2026-10-14", @"notes": @[@{@"type": @"added", @"text": @"a"}]},
        @{@"version": @"1.2", @"notes": @[@{@"type": @"notice", @"text": @"already installed"}]},
    ]);
    CDRUpdateDecision *d = [self decideInstalled:@"1.2" manifest:m state:nil
                                            soak:CDRSoakDurationOff breakThrough:NO];
    CDRAppRowModel *row = [self modelWithInstalled:@"1.2" decision:d manifest:m];

    XCTAssertEqual(row.section, CDRAppRowSectionUpdates);
    XCTAssertEqualObjects(row.advertisedVersion, @"1.4");
    XCTAssertEqualObjects(row.versionPairDisplay, @"1.2 → 1.4");
    // Dots: the advertised release's types only — not the skipped version's.
    XCTAssertEqual(row.noteTypes, CDRReleaseNoteTypeSetRemoved | CDRReleaseNoteTypeSetFixed);
    XCTAssertEqualObjects([row.releases valueForKey:@"version"], (@[@"1.4", @"1.3"]));
    XCTAssertEqualObjects(row.includedVersions, (@[@"1.3"]));
    XCTAssertEqual(row.releases.firstObject.undisplayableNoteCount, 1u);
    XCTAssertNotNil(row.releaseDate);
    XCTAssertEqualObjects(row.artifactSize, @19293798);
    XCTAssertEqualObjects(row.changelogURL.absoluteString, @"https://example.com/changelog");
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Update available");
    XCTAssertEqual(row.stateTone, CDRAppRowTonePrimary);
}

- (void)testDeferredRowKeepsItsDotsAndSitsUnderUpdates {
    CDRManifest *m = ManifestWithNotes(@"1.1", @[@[@"fixed", @"f"]], nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil
                                            soak:CDRSoakDurationOneWeek breakThrough:NO];
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];
    XCTAssertEqual(row.state, CDRAppRowStateDeferred);
    XCTAssertEqual(row.section, CDRAppRowSectionUpdates);
    XCTAssertEqual(row.noteTypes, CDRReleaseNoteTypeSetFixed);
    XCTAssertEqualObjects(row.deferredUntil, d.deferredUntil);
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Deferred · 7 days left");
    XCTAssertEqual(row.stateTone, CDRAppRowToneSecondary);
}

- (void)testRetractedPendingRowNeedsYouWithAHollowDotAndGotIt {
    CDRAppUpdateState *state = [[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now]
        stateByNotingNotifiedVersion:@"1.1" build:nil at:self.now];
    CDRManifest *m = ManifestWithNotes(@"1.0", @[@[@"fixed", @"notes of the build already installed"]], nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:state
                                            soak:CDRSoakDurationOff breakThrough:NO];
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];

    XCTAssertEqual(row.state, CDRAppRowStateRetracted);
    XCTAssertEqual(row.section, CDRAppRowSectionNeedsYou);
    XCTAssertEqualObjects(row.retractedVersion, @"1.1");
    // The only dot is Conductor's own Retracted ring; the manifest's notes
    // describe a build that isn't an update and are not shown.
    XCTAssertEqual(row.noteTypes, CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqual(row.releases.count, 0u);
    XCTAssertNil(row.advertisedVersion);
    XCTAssertEqualObjects(row.versionPairDisplay, @"1.0");
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"1.1 was retracted");
    XCTAssertEqual(row.stateTone, CDRAppRowToneAttention);
    XCTAssertTrue(row.actions & CDRAppRowActionAcknowledge);
}

- (void)testUpToDateRowShowsNoUpdateDataEvenIfTheManifestHasNotes {
    CDRManifest *m = ManifestWithNotes(@"1.0", @[@[@"added", @"what 1.0 added"]], nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil
                                            soak:CDRSoakDurationOff breakThrough:NO];
    CDRAppRowModel *row = [self modelWithInstalled:@"1.0" decision:d manifest:m];
    XCTAssertEqual(row.state, CDRAppRowStateUpToDate);
    XCTAssertEqual(row.section, CDRAppRowSectionUpToDate);
    XCTAssertEqual(row.noteTypes, CDRReleaseNoteTypeSetNone);
    XCTAssertEqual(row.releases.count, 0u);
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Up to date");
}

- (void)testWorkingAndParkedRowsKeepTheUpdateTheyAreInstalling {
    CDRManifest *m = ManifestWithNotes(@"1.1", @[@[@"improved", @"i"]], nil);
    CDRAppRegistration *reg = [self registrationWithInstalledVersion:@"1.0"];
    CDRAppRowModel *working = [CDRAppRowModel modelForRegistration:reg lastDecision:nil decidedManifest:m
                                                         lastError:nil ignored:NO
                                                    operationPhase:CDRUpdatePhaseDownloading parked:NO];
    XCTAssertEqual(working.section, CDRAppRowSectionUpdates);
    XCTAssertEqualObjects(working.versionPairDisplay, @"1.0 → 1.1");
    XCTAssertEqual(working.noteTypes, CDRReleaseNoteTypeSetImproved);
    XCTAssertEqualObjects([working shortStateLineAsOf:self.now], @"Downloading…");

    CDRAppRowModel *parked = [CDRAppRowModel modelForRegistration:reg lastDecision:nil decidedManifest:m
                                                        lastError:nil ignored:NO
                                                   operationPhase:CDRUpdatePhaseAwaitingQuit parked:YES];
    XCTAssertEqual(parked.section, CDRAppRowSectionUpdates);
    XCTAssertEqualObjects(parked.advertisedVersion, @"1.1");
}

- (void)testUncheckedFailedAndIgnoredRowsAreNeverFiledAsUpToDate {
    CDRAppRegistration *reg = [self registrationWithInstalledVersion:@"1.0"];
    CDRAppRowModel *unknown = [CDRAppRowModel modelForRegistration:reg lastDecision:nil decidedManifest:nil
                                                         lastError:nil ignored:NO
                                                    operationPhase:CDRUpdatePhaseIdle parked:NO];
    NSError *error = CDRError(CDRErrorManifestUnreachable, kBundleID, nil, nil);
    CDRAppRowModel *failed = [CDRAppRowModel modelForRegistration:reg lastDecision:nil decidedManifest:nil
                                                        lastError:error ignored:NO
                                                   operationPhase:CDRUpdatePhaseIdle parked:NO];
    CDRAppRowModel *ignored = [CDRAppRowModel modelForRegistration:reg lastDecision:nil decidedManifest:nil
                                                         lastError:nil ignored:YES
                                                    operationPhase:CDRUpdatePhaseIdle parked:NO];
    for (CDRAppRowModel *row in @[unknown, failed, ignored]) {
        XCTAssertEqual(row.section, CDRAppRowSectionNotChecked);
        XCTAssertNotEqualObjects([row shortStateLineAsOf:self.now], @"Up to date");
    }
    XCTAssertEqualObjects(failed.errorDescription, error.localizedDescription);
}

- (void)testContextSuppliesTheDeveloperName {
    CDRAppRegistration *reg = [self registrationWithInstalledVersion:@"1.0"];
    CDRAppRowContext *context = [[CDRAppRowContext alloc] init];
    context.developerName = @"Cedar Syntax LLC";
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:reg lastDecision:nil decidedManifest:nil
                                                     lastError:nil ignored:NO
                                                operationPhase:CDRUpdatePhaseIdle parked:NO context:context];
    XCTAssertEqualObjects(row.developerName, @"Cedar Syntax LLC");
    XCTAssertEqualObjects(row.appURL, reg.appURL);
    XCTAssertEqualObjects(row.installedVersion, @"1.0");
}

#pragma mark - Holds and major stops (CND-5)

- (CDRUpdateDecision *)decideInstalled:(NSString *)installed manifest:(CDRManifest *)manifest
                           stopAtMajor:(BOOL)stopAtMajor {
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    prefs.stopAtMajorVersions = stopAtMajor;
    return [CDRUpdatePolicy decisionForRegistration:[self registrationWithInstalledVersion:installed]
                                           manifest:manifest state:nil preferences:[prefs copy]
                                       breakThrough:NO now:self.now];
}

- (void)testHeldRowNeedsYouAndInstallsOnlyByItsOwnButton {
    CDRManifest *m = ManifestWithNotes(@"1.4", @[@[@"fixed", @"f"], @[@"removed", @"r"]], nil);
    CDRUpdateDecision *d = [self decideInstalled:@"1.3" manifest:m stopAtMajor:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeHeld);
    CDRAppRowModel *row = [self modelWithInstalled:@"1.3" decision:d manifest:m];

    XCTAssertEqual(row.state, CDRAppRowStateHeld);
    XCTAssertEqual(row.section, CDRAppRowSectionNeedsYou);
    XCTAssertEqual(row.heldTypes, CDRReleaseNoteTypeSetRemoved);
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Held · includes a removal");
    XCTAssertEqual(row.stateTone, CDRAppRowToneAttention);
    XCTAssertTrue(row.actions & CDRAppRowActionInstall);
    XCTAssertTrue(row.contributesToBadge);
    XCTAssertEqualObjects(row.availableVersion, @"1.4");
    XCTAssertEqualObjects(row.versionPairDisplay, @"1.3 → 1.4");
    XCTAssertTrue([row.stateLine containsString:@"held for manual install"]);
    XCTAssertTrue([row.stateLine containsString:@"includes a removal"]);
}

- (void)testStoppedAtMajorRowOffersAlwaysAllowAndInstall {
    CDRManifest *m = ManifestWithNotes(@"1.0", @[@[@"added", @"a"]], nil);
    CDRUpdateDecision *d = [self decideInstalled:@"0.9" manifest:m stopAtMajor:YES];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeStoppedAtMajor);
    CDRAppRowModel *row = [self modelWithInstalled:@"0.9" decision:d manifest:m];

    XCTAssertEqual(row.state, CDRAppRowStateStoppedAtMajor);
    XCTAssertEqual(row.section, CDRAppRowSectionNeedsYou);
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Stopped at major version");
    XCTAssertTrue(row.actions & CDRAppRowActionInstall);
    XCTAssertTrue(row.actions & CDRAppRowActionAlwaysAllowMajor);
    XCTAssertEqual(row.heldTypes, CDRReleaseNoteTypeSetNone);
    XCTAssertTrue([row.stateLine containsString:@"stopped at major version"]);
}

- (void)testHeldAndStoppedTogetherShowTheMajorStopAndKeepTheHeldTypes {
    CDRManifest *m = ManifestWithNotes(@"1.0", @[@[@"removed", @"r"]], nil);
    CDRUpdateDecision *d = [self decideInstalled:@"0.9" manifest:m stopAtMajor:YES];
    CDRAppRowModel *row = [self modelWithInstalled:@"0.9" decision:d manifest:m];
    XCTAssertEqual(row.state, CDRAppRowStateStoppedAtMajor);
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Stopped at major version");
    XCTAssertEqual(row.heldTypes, CDRReleaseNoteTypeSetRemoved);
}

- (void)testDeferredRowOffersUpdateNowAndNamesTheDeferral {
    CDRManifest *m = ManifestWithNotes(@"1.1", @[@[@"fixed", @"f"]], nil);
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    prefs.soakDuration = CDRSoakDurationThreeDays;
    CDRAppRegistration *reg = [self registrationWithInstalledVersion:@"1.0"];
    CDRUpdateDecision *d = [CDRUpdatePolicy decisionForRegistration:reg manifest:m state:nil
                                                        preferences:[prefs copy] breakThrough:NO now:self.now];
    CDRAppRowContext *context = [[CDRAppRowContext alloc] init];
    context.preferences = [prefs copy];
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:reg lastDecision:d decidedManifest:m
                                                     lastError:nil ignored:NO
                                                operationPhase:CDRUpdatePhaseIdle parked:NO context:context];
    XCTAssertEqual(row.state, CDRAppRowStateDeferred);
    XCTAssertTrue(row.actions & CDRAppRowActionInstallDeferred);
    XCTAssertFalse(row.actions & CDRAppRowActionInstall, @"a deferred update is never one plain click from installing");
    XCTAssertEqualObjects(row.deferralDurationName, @"3 days");
    XCTAssertEqualObjects([row shortStateLineAsOf:self.now], @"Deferred · 3 days left");
}

#pragma mark - Unacknowledged retraction notices (CND-6)

- (void)testAPendingRetractionNoticeKeepsTheRowRetractedAfterTheDecisionHasPassed {
    NSDate *advertised = [self.now dateByAddingTimeInterval:-2 * 86400];
    NSDate *pulled = [self.now dateByAddingTimeInterval:-86400];
    CDRAppRowContext *context = [[CDRAppRowContext alloc] init];
    context.pendingRetraction = [CDRRetractionNotice noticeWithVersion:@"1.2" advertisedAt:advertised pulledAt:pulled];
    CDRAppRegistration *reg = [self registrationWithInstalledVersion:@"1.1"];

    // A later check that says "up to date"…
    CDRManifest *m = ManifestWithVersion(@"1.1", nil);
    CDRUpdateDecision *upToDate = [CDRUpdatePolicy decisionForRegistration:reg manifest:m state:nil
                                                               preferences:PrefsWithSoak(CDRSoakDurationOff)
                                                              breakThrough:NO now:self.now];
    XCTAssertEqual(upToDate.outcome, CDRUpdateOutcomeUpToDate);
    // …and no decision at all (just relaunched): both still show the notice.
    for (CDRUpdateDecision *decision in @[upToDate, [NSNull null]]) {
        CDRUpdateDecision *d = [decision isKindOfClass:[NSNull class]] ? nil : decision;
        CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:reg lastDecision:d decidedManifest:d ? m : nil
                                                         lastError:nil ignored:NO
                                                    operationPhase:CDRUpdatePhaseIdle parked:NO context:context];
        XCTAssertEqual(row.state, CDRAppRowStateRetracted);
        XCTAssertEqualObjects(row.retractedVersion, @"1.2");
        XCTAssertEqualObjects(row.retractionAdvertisedDate, advertised);
        XCTAssertEqualObjects(row.retractionPulledDate, pulled);
        XCTAssertTrue(row.actions & CDRAppRowActionAcknowledge);
        XCTAssertEqual(row.noteTypes, CDRReleaseNoteTypeSetRetracted);
    }

    // Without a notice the same decision is plainly up to date.
    CDRAppRowModel *plain = [CDRAppRowModel modelForRegistration:reg lastDecision:upToDate decidedManifest:m
                                                       lastError:nil ignored:NO
                                                  operationPhase:CDRUpdatePhaseIdle parked:NO];
    XCTAssertEqual(plain.state, CDRAppRowStateUpToDate);

    // A real update on offer outranks an old notice.
    CDRManifest *newer = ManifestWithVersion(@"1.3", nil);
    CDRUpdateDecision *available = [CDRUpdatePolicy decisionForRegistration:reg manifest:newer state:nil
                                                                preferences:PrefsWithSoak(CDRSoakDurationOff)
                                                               breakThrough:NO now:self.now];
    CDRAppRowModel *row = [CDRAppRowModel modelForRegistration:reg lastDecision:available decidedManifest:newer
                                                     lastError:nil ignored:NO
                                                operationPhase:CDRUpdatePhaseIdle parked:NO context:context];
    XCTAssertEqual(row.state, CDRAppRowStateAvailable);
}

- (void)testRetractionNoticeStoreRoundTripsAndToleratesGarbage {
    NSString *suite = [NSString stringWithFormat:@"cdr-notice-tests-%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    XCTAssertNil(CDRRetractionNoticeForBundleID(kBundleID, defaults));

    NSDate *pulled = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
    CDRSetRetractionNotice([CDRRetractionNotice noticeWithVersion:@"1.2" advertisedAt:nil pulledAt:pulled],
                           kBundleID, defaults);
    CDRRetractionNotice *read = CDRRetractionNoticeForBundleID(kBundleID, defaults);
    XCTAssertEqualObjects(read.version, @"1.2");
    XCTAssertEqualObjects(read.pulledAt, pulled);
    XCTAssertNil(read.advertisedAt);
    XCTAssertNil(CDRRetractionNoticeForBundleID(@"com.example.other", defaults));

    CDRSetRetractionNotice(nil, kBundleID, defaults);
    XCTAssertNil(CDRRetractionNoticeForBundleID(kBundleID, defaults));
    XCTAssertNil([defaults objectForKey:CDRRetractionNoticesDefaultsKey]);

    for (id garbage in @[@"x", @{kBundleID: @"x"}, @{kBundleID: @{@"version": @"1.2"}},
                         @{kBundleID: @{@"version": @7, @"pulled_at": pulled}}]) {
        [defaults setObject:garbage forKey:CDRRetractionNoticesDefaultsKey];
        XCTAssertNil(CDRRetractionNoticeForBundleID(kBundleID, defaults));
    }
    [defaults removePersistentDomainForName:suite];
}

@end
