//
//  CDRNotificationGateTests.m
//  ConductorTests
//
//  The truth table for CDRDecisionWarrantsNotification: which check outcomes
//  reach the user as a notification (vs quiet row/badge state only).
//

#import <XCTest/XCTest.h>
#import "CDRUpdateController.h"
#import "CDRAppRegistration.h"
#import "CDRAppUpdateState.h"
#import "CDRManifest.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdatePreferences.h"

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

@interface CDRNotificationGateTests : XCTestCase
@property (nonatomic) NSURL *fixtureRoot;
@property (nonatomic) NSDate *now;
@end

@implementation CDRNotificationGateTests

- (void)setUp {
    [super setUp];
    self.fixtureRoot = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-notifgate-tests-%@", NSUUID.UUID.UUIDString]
                        isDirectory:YES];
    self.now = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:self.fixtureRoot error:NULL];
    [super tearDown];
}

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
    } options:0 error:NULL];
    [json writeToURL:[resources URLByAppendingPathComponent:@"conductor.json"] atomically:YES];
    return [CDRAppRegistration registrationForAppAtURL:appURL error:NULL];
}

static CDRManifest *ManifestWithVersion(NSString *version) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"conductor_manifest": @1,
        @"bundle_id": kBundleID,
        @"version": version,
        @"url": @"https://example.com/app.dmg",
    } options:0 error:NULL];
    return [CDRManifest manifestWithData:data error:NULL];
}

- (CDRUpdateDecision *)decideInstalled:(NSString *)installed
                              manifest:(CDRManifest *)manifest
                                 state:(CDRAppUpdateState *)state
                                  soak:(CDRSoakDuration)soak {
    return [CDRUpdatePolicy decisionForRegistration:[self registrationWithInstalledVersion:installed]
                                           manifest:manifest
                                              state:state
                                       preferences:PrefsWithSoak(soak)
                                       breakThrough:NO
                                                now:self.now];
}

- (CDRAppUpdateState *)stateNotifiedAbout:(NSString *)version {
    return [[[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:version build:nil at:self.now]
        stateByNotingNotifiedVersion:version build:nil at:self.now];
}

- (void)testFirstAvailableNotifies {
    CDRManifest *m = ManifestWithVersion(@"1.1");
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:nil soak:CDRSoakDurationOff];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertTrue(CDRDecisionWarrantsNotification(d, nil, m));
}

- (void)testResightingOfNotifiedVersionIsQuiet {
    CDRManifest *m = ManifestWithVersion(@"1.1");
    CDRAppUpdateState *previous = [self stateNotifiedAbout:@"1.1"];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:previous soak:CDRSoakDurationOff];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertFalse(CDRDecisionWarrantsNotification(d, previous, m));
}

- (void)testNewerVersionAfterEarlierNotificationNotifiesAgain {
    CDRManifest *m = ManifestWithVersion(@"1.2");
    CDRAppUpdateState *previous = [self stateNotifiedAbout:@"1.1"];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:previous soak:CDRSoakDurationOff];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeAvailable);
    XCTAssertTrue(CDRDecisionWarrantsNotification(d, previous, m));
}

- (void)testRetractedPendingAlwaysNotifies {
    // Self-limiting: the decision clears the notified memory, so this fires
    // once ever per retraction.
    CDRManifest *m = ManifestWithVersion(@"1.0");
    CDRAppUpdateState *previous = [self stateNotifiedAbout:@"1.1"];
    CDRUpdateDecision *d = [self decideInstalled:@"1.0" manifest:m state:previous soak:CDRSoakDurationOff];
    XCTAssertEqual(d.outcome, CDRUpdateOutcomeRetractedPending);
    XCTAssertTrue(CDRDecisionWarrantsNotification(d, previous, m));
}

- (void)testQuietOutcomesStayQuiet {
    // Deferred.
    CDRManifest *newer = ManifestWithVersion(@"1.1");
    CDRUpdateDecision *deferred = [self decideInstalled:@"1.0" manifest:newer state:nil
                                                   soak:CDRSoakDurationOneWeek];
    XCTAssertEqual(deferred.outcome, CDRUpdateOutcomeDeferred);
    XCTAssertFalse(CDRDecisionWarrantsNotification(deferred, nil, newer));

    // Up to date.
    CDRManifest *same = ManifestWithVersion(@"1.0");
    CDRUpdateDecision *upToDate = [self decideInstalled:@"1.0" manifest:same state:nil
                                                   soak:CDRSoakDurationOff];
    XCTAssertEqual(upToDate.outcome, CDRUpdateOutcomeUpToDate);
    XCTAssertFalse(CDRDecisionWarrantsNotification(upToDate, nil, same));

    // Dropped silently: a soaking version vanished — no promise was made.
    CDRAppUpdateState *soaking = [[CDRAppUpdateState emptyStateWithBundleID:kBundleID at:self.now]
        stateBySeeingVersion:@"1.1" build:nil at:self.now];
    CDRUpdateDecision *dropped = [self decideInstalled:@"1.0" manifest:same state:soaking
                                                  soak:CDRSoakDurationOneWeek];
    XCTAssertEqual(dropped.outcome, CDRUpdateOutcomeDroppedSilently);
    XCTAssertFalse(CDRDecisionWarrantsNotification(dropped, soaking, same));

    // State B is the controller's once-per-launch surface, not this gate's.
    CDRAppUpdateState *notified = [self stateNotifiedAbout:@"1.1"];
    CDRUpdateDecision *stateB = [self decideInstalled:@"1.1" manifest:same state:notified
                                                 soak:CDRSoakDurationOff];
    XCTAssertEqual(stateB.outcome, CDRUpdateOutcomeRetractedInstalled);
    XCTAssertFalse(CDRDecisionWarrantsNotification(stateB, notified, same));
}

#pragma mark - Held and major-stop updates (CND-5)

- (void)testHeldAndStoppedUpdatesNotifyOncePerVersionLikeAvailableOnes {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"conductor_manifest": @1, @"bundle_id": kBundleID, @"version": @"2.0",
        @"url": @"https://example.com/app.dmg",
        @"notes": @[@{@"type": @"removed", @"text": @"gone"}],
    } options:0 error:NULL];
    CDRManifest *m = [CDRManifest manifestWithData:data error:NULL];

    for (NSNumber *stop in @[@NO, @YES]) {
        CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
        prefs.stopAtMajorVersions = stop.boolValue;
        CDRUpdateDecision *first = [CDRUpdatePolicy decisionForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                                   manifest:m state:nil preferences:[prefs copy]
                                                               breakThrough:NO now:self.now];
        XCTAssertEqual(first.outcome, stop.boolValue ? CDRUpdateOutcomeStoppedAtMajor : CDRUpdateOutcomeHeld);
        XCTAssertTrue(CDRDecisionWarrantsNotification(first, nil, m), @"first sighting is announced");

        CDRUpdateDecision *again = [CDRUpdatePolicy decisionForRegistration:[self registrationWithInstalledVersion:@"1.0"]
                                                                   manifest:m state:first.stateAfterCheck
                                                                preferences:[prefs copy] breakThrough:NO now:self.now];
        XCTAssertEqual(again.outcome, first.outcome);
        XCTAssertFalse(CDRDecisionWarrantsNotification(again, first.stateAfterCheck, m), @"re-sightings are quiet");
    }
}

@end
