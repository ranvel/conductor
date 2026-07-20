//
//  CDRUpdatePolicyTests.m
//  ConductorTests
//
//  Every transition in the deferral.md (D1–D13) and retraction.md (R1–R11)
//  state tables, plus the fixed copy strings. Pure — fixed `now`, no I/O
//  beyond the throwaway registration bundles.
//

#import <XCTest/XCTest.h>
#import "CDRUpdatePolicy.h"
#import "CDRAppRegistration.h"
#import "CDRAppUpdateState.h"
#import "CDRManifest.h"

static const NSTimeInterval kHour = 60.0 * 60.0;
static const NSTimeInterval kDay = 24.0 * kHour;

@interface CDRUpdatePolicyTests : XCTestCase
@property (nonatomic) NSURL *fixtureRoot;
@property (nonatomic) NSDate *now;
@end

@implementation CDRUpdatePolicyTests

static NSString * const kBundleID = @"com.example.app";

- (void)setUp {
    [super setUp];
    self.fixtureRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-policy-tests-%@", NSUUID.UUID.UUIDString]
                        isDirectory:YES];
    self.now = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.fixtureRoot error:NULL];
    [super tearDown];
}

#pragma mark - Fixtures

/// A minimal on-disk bundle: registrations are only constructible from real
/// bundles, which keeps the fixture honest about where installed versions
/// come from (Info.plist, never the manifest).
- (CDRAppRegistration *)registrationWithInstalledVersion:(NSString *)version build:(NSString *)build {
    NSURL *appURL = [[self.fixtureRoot URLByAppendingPathComponent:NSUUID.UUID.UUIDString]
        URLByAppendingPathComponent:@"TestApp.app"];
    NSURL *resources = [appURL URLByAppendingPathComponent:@"Contents/Resources"];
    [[NSFileManager defaultManager] createDirectoryAtURL:resources
                             withIntermediateDirectories:YES attributes:nil error:NULL];

    NSMutableDictionary *info = [@{
        @"CFBundleIdentifier": kBundleID,
        @"CFBundleShortVersionString": version,
    } mutableCopy];
    if (build) info[@"CFBundleVersion"] = build;
    [info writeToURL:[appURL URLByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];

    NSData *json = [NSJSONSerialization dataWithJSONObject:@{
        @"conductor": @1,
        @"update_url": @"https://example.com/manifest.json",
        @"vendor_url": @"https://example.com",
    } options:0 error:NULL];
    [json writeToURL:[resources URLByAppendingPathComponent:@"conductor.json"] atomically:YES];

    NSError *error = nil;
    CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:appURL error:&error];
    XCTAssertNotNil(reg, @"fixture registration failed: %@", error);
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

/// State that observed `seen` at `seenAt` (and was notified about `notified`
/// at `notifiedAt` when non-nil).
- (CDRAppUpdateState *)stateSeen:(NSString *)seen at:(NSDate *)seenAt
                        notified:(NSString *)notified at:(NSDate *)notifiedAt {
    CDRAppUpdateState *state = [[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:seenAt]
        stateBySeeingVersion:seen build:nil at:seenAt];
    if (notified) {
        NSDate *when = notifiedAt ?: seenAt;
        if ([notified isEqualToString:seen]) {
            state = [state stateByNotingNotifiedVersion:notified build:nil at:when];
        } else {
            // Notified about an earlier version, then observed a newer one.
            state = [[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:when]
                stateBySeeingVersion:notified build:nil at:when]
                stateByNotingNotifiedVersion:notified build:nil at:when];
            state = [state stateBySeeingVersion:seen build:nil at:seenAt];
        }
    }
    return state;
}

- (CDRUpdateDecision *)decideInstalled:(NSString *)installed
                              manifest:(CDRManifest *)manifest
                                 state:(CDRAppUpdateState *)state
                                  soak:(CDRSoakDuration)soak
                          breakThrough:(BOOL)breakThrough {
    return [CDRUpdatePolicy decisionForRegistration:[self registrationWithInstalledVersion:installed build:nil]
                                           manifest:manifest
                                              state:state
                                       soakDuration:soak
                                       breakThrough:breakThrough
                                                now:self.now];
}

#pragma mark - Deferral table (deferral.md)

- (void)testD1_SoakOffSurfacesImmediately {
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:nil soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertEqualObjects(d.stateAfterCheck.lastSeenVersion, @"1.1");
    XCTAssertEqualObjects(d.stateAfterCheck.lastNotifiedVersion, @"1.1");
    XCTAssertEqualObjects(d.stateAfterCheck.firstSeenByVersion[@"1.1"], self.now);
}

- (void)testD2_FirstObservationDefers {
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:nil soak:CDRSoakDurationOneDay breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertEqualObjects(d.deferredUntil, [self.now dateByAddingTimeInterval:kDay]);
    XCTAssertNil(d.stateAfterCheck.lastNotifiedVersion);
    XCTAssertEqualObjects(d.stateAfterCheck.firstSeenByVersion[@"1.1"], self.now);
}

- (void)testD3_MaturedSoakSurfaces {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-25 * kHour]
                                      notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOneDay breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertEqualObjects(d.stateAfterCheck.lastNotifiedVersion, @"1.1");
    XCTAssertEqualObjects(d.stateAfterCheck.notifiedAt, self.now);
}

- (void)testD4_UnmaturedWeekSoakDefers {
    NSDate *firstSeen = [self.now dateByAddingTimeInterval:-25 * kHour];
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:firstSeen notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertEqualObjects(d.deferredUntil, [firstSeen dateByAddingTimeInterval:7 * kDay]);
}

- (void)testD5_MaturityKeysOnCurrentSetting {
    // Observed 25h ago under a 1-week soak; the user then shortened the
    // setting to 1 day — the same first_seen is now mature.
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-25 * kHour]
                                      notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOneDay breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
}

- (void)testD6_NewerVersionSupersedesSoakingOne {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-25 * kHour]
                                      notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.2", nil)
                                           state:state soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertEqualObjects(d.deferredUntil, [self.now dateByAddingTimeInterval:7 * kDay]);
    XCTAssertEqualObjects(d.stateAfterCheck.lastSeenVersion, @"1.2");
    XCTAssertEqualObjects(d.stateAfterCheck.firstSeenByVersion[@"1.2"], self.now);
    XCTAssertNil(d.stateAfterCheck.firstSeenByVersion[@"1.1"], @"superseded soak must be pruned");
}

- (void)testD7_NeverNotifyANonLatestVersion {
    // 1.1's soak would be mature under the 1-day setting, but 1.2 is now the
    // latest — 1.2 gets its own soak; 1.1 must not be surfaced.
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-25 * kHour]
                                      notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.2", nil)
                                           state:state soak:CDRSoakDurationOneDay breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertNil(d.stateAfterCheck.lastNotifiedVersion);
}

- (void)testD8_UrgencyBypassesSoakAndMarksNotified {
    NSDictionary<NSString *, NSNumber *> *cases = @{
        @"system_risk": @(CDRUrgencySystemRisk),
        @"data_loss": @(CDRUrgencyDataLoss),
        @"data_exfiltration": @(CDRUrgencyDataExfiltration),
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *token, NSNumber *expected, BOOL *stop) {
        CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", token)
                                               state:nil soak:CDRSoakDurationOneWeek breakThrough:NO];
        XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable, @"%@", token);
        XCTAssertEqual(d.urgency, (CDRUrgency)expected.integerValue);
        // Urgency-surfaced counts as notified — retraction loudness applies.
        XCTAssertEqualObjects(d.stateAfterCheck.lastNotifiedVersion, @"1.1");
    }];
}

- (void)testD9_BreakThroughOffersWithoutMarkingNotified {
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:nil soak:CDRSoakDurationOneDay breakThrough:YES];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferredOffered);
    XCTAssertEqualObjects(d.deferredUntil, [self.now dateByAddingTimeInterval:kDay]);
    // Only the user's install consent marks it notified (deferral.md).
    XCTAssertNil(d.stateAfterCheck.lastNotifiedVersion);
}

- (void)testD10_BreakThroughIsNoOpWhenMatured {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-25 * kHour]
                                      notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOneDay breakThrough:YES];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
}

- (void)testD11_BreakThroughIsNoOpWhenUpToDate {
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0", nil)
                                           state:nil soak:CDRSoakDurationOneDay breakThrough:YES];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeUpToDate);
}

- (void)testD12_AlreadyNotifiedVersionReShowsWithoutSoakRegate {
    NSDate *notifiedAt = [self.now dateByAddingTimeInterval:-kHour];
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:notifiedAt notified:@"1.1" at:notifiedAt];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
    // The promise was already made; notified_at is not refreshed.
    XCTAssertEqualObjects(d.stateAfterCheck.notifiedAt, notifiedAt);
}

- (void)testD13_MissingFirstSeenTreatedAsNow {
    // A state record exists but has no first_seen for the advertised version
    // (degenerate/pruned file) — the soak clock starts now; never surface on
    // a clock that cannot be verified.
    CDRAppUpdateState *state = [[CDRAppUpdateState alloc] initWithBundleID:kBundleID
                                                           lastSeenVersion:@"1.1"
                                                             lastSeenBuild:nil
                                                        firstSeenByVersion:@{}
                                                       lastNotifiedVersion:nil
                                                         lastNotifiedBuild:nil
                                                                notifiedAt:nil
                                                                 updatedAt:[self.now dateByAddingTimeInterval:-2 * kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOneDay breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertEqualObjects(d.deferredUntil, [self.now dateByAddingTimeInterval:kDay]);
}

#pragma mark - Retraction table (retraction.md)

- (void)testR1_StateA_NotifiedNotInstalled_LoudAndCleared {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0", nil)
                                           state:state soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeRetractedPending);
    XCTAssertEqualObjects(d.retractedVersion, @"1.1");
    XCTAssertNil(d.stateAfterCheck.lastNotifiedVersion);
    XCTAssertEqualObjects(d.stateAfterCheck.lastSeenVersion, @"1.0");
}

- (void)testR2_StateALoudnessIsOneTimeEver {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *first = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0", nil)
                                               state:state soak:CDRSoakDurationOff breakThrough:NO];
    CDRUpdateDecision *second = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0", nil)
                                                state:first.stateAfterCheck soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(second.outcome, CDRUpdateOutcomeUpToDate);
}

- (void)testR3_StateB_RetractedBuildInstalled_NotifiedRetained {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.0", nil)
                                           state:state soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeRetractedInstalled);
    XCTAssertEqualObjects(d.retractedVersion, @"1.1");
    // Retained so the state persists across launches until the manifest
    // advertises ≥ installed again (retraction.md).
    XCTAssertEqualObjects(d.stateAfterCheck.lastNotifiedVersion, @"1.1");
}

- (void)testR4_StateBPersistsAcrossChecks {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *first = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.0", nil)
                                               state:state soak:CDRSoakDurationOff breakThrough:NO];
    CDRUpdateDecision *second = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.0", nil)
                                                state:first.stateAfterCheck soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(second.outcome, CDRUpdateOutcomeRetractedInstalled);
}

- (void)testR5_StateBExitsWhenVendorRePromotes {
    CDRAppUpdateState *state = [self stateSeen:@"1.0" at:self.now
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeUpToDate);
}

- (void)testR6_StateBExitsWhenVendorShipsNewerFix {
    CDRAppUpdateState *state = [self stateSeen:@"1.0" at:self.now
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.2", nil)
                                           state:state soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
}

- (void)testR7_VendorFixAfterStateBSoaksLikeAnyVersion {
    // Deliberate: the post-recall fix gets its own soak. The vendor's escape
    // hatch for shipping it immediately is the urgency flag, not the recall.
    CDRAppUpdateState *state = [self stateSeen:@"1.0" at:self.now
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.2", nil)
                                           state:state soak:CDRSoakDurationOneWeek breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDeferred);
}

- (void)testR8_NeverSurfacedVersionDropsSilently {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:nil at:nil];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0", nil)
                                           state:state soak:CDRSoakDurationOneWeek breakThrough:NO];
    // Presents to the user identically to UpToDate; no loudness is owed for a
    // promise never made.
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeDroppedSilently);
    XCTAssertEqualObjects(d.stateAfterCheck.lastSeenVersion, @"1.0");
    XCTAssertNil(d.stateAfterCheck.lastNotifiedVersion);
}

- (void)testR9_NoFalseRecallWithoutNotificationMemory {
    // Manually installed beta: installed 2.0 > manifest 1.9, but Conductor
    // never notified about anything — this must NOT read as a recall.
    CDRUpdateDecision *d = [self decideInstalled:@"2.0" manifest:ManifestWithVersion(@"1.9", nil)
                                           state:nil soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeUpToDate);
}

- (void)testR10_IntermediateVersionStillYieldsStateA {
    // Notified 1.1, installed 1.0, vendor re-points to 1.0.5: the promise
    // about 1.1 is broken → State A now; 1.0.5 is ingested and evaluated
    // normally on the next check.
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0.5", nil)
                                           state:state soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeRetractedPending);
    XCTAssertEqualObjects(d.retractedVersion, @"1.1");
    XCTAssertEqualObjects(d.stateAfterCheck.lastSeenVersion, @"1.0.5");
    XCTAssertEqualObjects(d.stateAfterCheck.firstSeenByVersion[@"1.0.5"], self.now);

    CDRUpdateDecision *next = [self decideInstalled:@"1.0" manifest:ManifestWithVersion(@"1.0.5", nil)
                                              state:d.stateAfterCheck soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(next.outcome, CDRUpdateOutcomeAvailable);
}

- (void)testR11_NotifiedThenInstalledIsUpToDate {
    CDRAppUpdateState *state = [self stateSeen:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]
                                      notified:@"1.1" at:[self.now dateByAddingTimeInterval:-kDay]];
    CDRUpdateDecision *d = [self decideInstalled:@"1.1" manifest:ManifestWithVersion(@"1.1", nil)
                                           state:state soak:CDRSoakDurationOff breakThrough:NO];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeUpToDate);
}

#pragma mark - Soak setting round-trip

- (void)testSoakDurationDefaultsTokens {
    XCTAssertEqual(CDRSoakDurationFromDefaultsToken(@"off"), CDRSoakDurationOff);
    XCTAssertEqual(CDRSoakDurationFromDefaultsToken(@"1d"), CDRSoakDurationOneDay);
    XCTAssertEqual(CDRSoakDurationFromDefaultsToken(@"1w"), CDRSoakDurationOneWeek);
    XCTAssertEqual(CDRSoakDurationFromDefaultsToken(@"garbage"), CDRSoakDurationOff);
    XCTAssertEqual(CDRSoakDurationFromDefaultsToken(nil), CDRSoakDurationOff);
    for (NSNumber *n in @[@(CDRSoakDurationOff), @(CDRSoakDurationOneDay), @(CDRSoakDurationOneWeek)]) {
        CDRSoakDuration duration = n.integerValue;
        XCTAssertEqual(CDRSoakDurationFromDefaultsToken(CDRSoakDurationDefaultsToken(duration)), duration);
    }
    XCTAssertEqual(CDRSoakDurationInterval(CDRSoakDurationOneDay), 24 * kHour);
    XCTAssertEqual(CDRSoakDurationInterval(CDRSoakDurationOneWeek), 7 * 24 * kHour);
}

#pragma mark - Copy

- (void)testUrgencyCopyIsVendorAttributed {
    NSDictionary<NSNumber *, NSString *> *cases = @{
        @(CDRUrgencySystemRisk): @"The developer has flagged Example 1.1 as fixing a vulnerability that puts the system at risk.",
        @(CDRUrgencyDataLoss): @"The developer has flagged Example 1.1 as fixing a bug that can cause data loss.",
        @(CDRUrgencyDataExfiltration): @"The developer has flagged Example 1.1 as fixing a potential data exfiltration issue.",
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSNumber *urgency, NSString *expected, BOOL *stop) {
        XCTAssertEqualObjects(CDRUrgencyNoticeCopy(urgency.integerValue, @"Example", @"1.1"), expected);
    }];
}

- (void)testDeferredOfferCopy {
    NSString *copy = CDRDeferredOfferCopy(@"Example", @"1.1", self.now);
    XCTAssertTrue([copy containsString:@"Example 1.1 is available"]);
    XCTAssertTrue([copy containsString:@"deferred until"]);
    XCTAssertTrue([copy containsString:@"by your update settings"]);
    XCTAssertTrue([copy containsString:@"Install anyway?"]);
}

- (void)testRetractedPendingCopy {
    NSString *copy = CDRRetractedPendingCopy(@"Example", @"1.1", @"1.0");
    XCTAssertEqualObjects(copy, @"Example: the developer retracted update 1.1. You already have the latest build (1.0).");
}

- (void)testRetractedInstalledCopy {
    NSString *copy = CDRRetractedInstalledCopy(@"Example", @"1.1");
    XCTAssertTrue([copy containsString:@"recalled build 1.1, which you have installed"]);
    XCTAssertTrue([copy containsString:@"does not downgrade automatically"]);
}

@end
