//
//  CDRUpdatePreferencesTests.m
//  ConductorTests
//
//  The v2 policy values: defaults round-trip, the Retracted invariant, the
//  interest-scheme rules, per-app overrides and the resolver.
//

#import <XCTest/XCTest.h>
#import "CDRUpdatePreferences.h"

@interface CDRUpdatePreferencesTests : XCTestCase
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic, copy) NSString *suiteName;
@end

@implementation CDRUpdatePreferencesTests

- (void)setUp {
    self.suiteName = [NSString stringWithFormat:@"cdr-prefs-tests-%@", NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:self.suiteName];
}

#pragma mark - Defaults

- (void)testFreshInstallDefaults {
    CDRUpdatePreferences *p = [CDRUpdatePreferences preferencesFromDefaults:self.defaults];
    XCTAssertEqualObjects(p, [CDRUpdatePreferences defaultPreferences]);
    XCTAssertEqual(p.soakDuration, CDRSoakDurationOff);
    XCTAssertFalse(p.stopAtMajorVersions);
    XCTAssertEqual(p.interestScheme, CDRInterestSchemeNormal);
    // Normal user: everything but Security (the Settings design).
    XCTAssertEqual(p.shownTypes, CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetSecurity);
    XCTAssertEqual(p.holdTypes, CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetRemoved
                   | CDRReleaseNoteTypeSetRetracted);
    XCTAssertTrue(p.requireNetworkApproval);
    XCTAssertTrue(p.policyExemptsApproval);
    XCTAssertFalse(p.exposesDeveloperDetail);
}

- (void)testEveryFieldRoundTripsThroughDefaults {
    CDRMutableUpdatePreferences *m = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    m.soakDuration = CDRSoakDurationThreeDays;
    m.stopAtMajorVersions = YES;
    m.shownTypes = CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetSecurity;
    m.holdTypes = CDRReleaseNoteTypeSetSecurity | CDRReleaseNoteTypeSetDisabled;
    m.requireNetworkApproval = NO;
    m.policyExemptsApproval = NO;
    [m writeToDefaults:self.defaults];

    CDRUpdatePreferences *read = [CDRUpdatePreferences preferencesFromDefaults:self.defaults];
    XCTAssertEqualObjects(read, [m copy]);
    XCTAssertEqual(read.soakDuration, CDRSoakDurationThreeDays);
    XCTAssertTrue(read.stopAtMajorVersions);
    XCTAssertEqual(read.interestScheme, CDRInterestSchemeCustom);
    XCTAssertEqual(read.shownTypes, CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetSecurity
                   | CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqual(read.holdTypes, CDRReleaseNoteTypeSetSecurity | CDRReleaseNoteTypeSetDisabled
                   | CDRReleaseNoteTypeSetRetracted);
    XCTAssertFalse(read.requireNetworkApproval);
    XCTAssertFalse(read.policyExemptsApproval);
}

- (void)testThreeDayDeferralTokenPersistsAndOldTokensAreUndisturbed {
    XCTAssertEqualObjects(CDRSoakDurationDefaultsToken(CDRSoakDurationThreeDays), @"3d");
    XCTAssertEqual(CDRSoakDurationFromDefaultsToken(@"3d"), CDRSoakDurationThreeDays);
    XCTAssertEqual(CDRSoakDurationInterval(CDRSoakDurationThreeDays), 3 * 86400.0);
    // The durable contract from before v2.
    XCTAssertEqual(CDRSoakDurationOff, 0);
    XCTAssertEqual(CDRSoakDurationOneDay, 1);
    XCTAssertEqual(CDRSoakDurationOneWeek, 2);
    XCTAssertEqualObjects(CDRSoakDurationDefaultsToken(CDRSoakDurationOneDay), @"1d");
    XCTAssertEqualObjects(CDRSoakDurationDefaultsToken(CDRSoakDurationOneWeek), @"1w");
    XCTAssertEqualObjects(CDRSoakDurationDefaultsToken(CDRSoakDurationOff), @"off");

    // Offered in order of length, whatever the enum order is.
    XCTAssertEqualObjects(CDRSoakDurationChoices(), (@[@(CDRSoakDurationOff), @(CDRSoakDurationOneDay),
                                                       @(CDRSoakDurationThreeDays), @(CDRSoakDurationOneWeek)]));
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSTimeInterval previous = -1;
    for (NSNumber *choice in CDRSoakDurationChoices()) {
        CDRSoakDuration duration = (CDRSoakDuration)choice.integerValue;
        [names addObject:CDRSoakDurationDisplayName(duration)];
        XCTAssertGreaterThan(CDRSoakDurationInterval(duration), previous);
        previous = CDRSoakDurationInterval(duration);
        XCTAssertEqual(CDRSoakDurationFromDefaultsToken(CDRSoakDurationDefaultsToken(duration)), duration);
    }
    XCTAssertEqualObjects(names, (@[@"Off", @"1 day", @"3 days", @"1 week"]));
}

#pragma mark - Garbage tolerance and the Retracted invariant

- (void)testGarbageStoredValuesFallBackFieldByField {
    [self.defaults setObject:@"fortnight" forKey:CDRSoakDurationDefaultsKey];
    [self.defaults setObject:@"maybe" forKey:CDRStopAtMajorVersionsDefaultsKey];
    [self.defaults setObject:@42 forKey:CDRInterestSchemeDefaultsKey];
    [self.defaults setObject:@"all of them" forKey:CDRShownNoteTypesDefaultsKey];
    [self.defaults setObject:@{@"notice": @YES} forKey:CDRHoldNoteTypesDefaultsKey];
    [self.defaults setObject:@"yes please" forKey:CDRRequireNetworkApprovalDefaultsKey];
    [self.defaults setObject:@[@1] forKey:CDRPolicyExemptsNetworkApprovalDefaultsKey];

    XCTAssertEqualObjects([CDRUpdatePreferences preferencesFromDefaults:self.defaults],
                          [CDRUpdatePreferences defaultPreferences]);
}

- (void)testRetractedCannotBeTurnedOffByDefaultsWrite {
    // `defaults write … CDRInterestScheme custom`, with Retracted left out of
    // both stored sets — and unknown keys mixed in.
    [self.defaults setObject:@"custom" forKey:CDRInterestSchemeDefaultsKey];
    [self.defaults setObject:@[@"added", @"bogus", @7] forKey:CDRShownNoteTypesDefaultsKey];
    [self.defaults setObject:@[] forKey:CDRHoldNoteTypesDefaultsKey];

    CDRUpdatePreferences *p = [CDRUpdatePreferences preferencesFromDefaults:self.defaults];
    XCTAssertEqual(p.shownTypes, CDRReleaseNoteTypeSetAdded | CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqual(p.holdTypes, CDRReleaseNoteTypeSetRetracted);

    // Nor through the mutable twin, a copy, or the resolver.
    CDRMutableUpdatePreferences *m = [p mutableCopy];
    m.shownTypes = CDRReleaseNoteTypeSetNone;
    m.holdTypes = CDRReleaseNoteTypeSetNone;
    XCTAssertEqual(m.shownTypes, CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqual(m.holdTypes, CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqual(((CDRUpdatePreferences *)[m copy]).holdTypes, CDRReleaseNoteTypeSetRetracted);

    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.shownTypes = @(CDRReleaseNoteTypeSetFixed);
    override.holdTypes = @(CDRReleaseNoteTypeSetNone);
    CDRUpdatePreferences *effective = [CDRPolicyResolver effectivePreferencesWithGlobal:p override:override];
    XCTAssertTrue(CDRReleaseNoteTypeSetContains(effective.shownTypes, CDRReleaseNoteTypeRetracted));
    XCTAssertTrue(CDRReleaseNoteTypeSetContains(effective.holdTypes, CDRReleaseNoteTypeRetracted));
}

- (void)testAPresetIgnoresWhateverCategorySetIsStored {
    [self.defaults setObject:@"everything" forKey:CDRInterestSchemeDefaultsKey];
    [self.defaults setObject:@[@"fixed"] forKey:CDRShownNoteTypesDefaultsKey];
    XCTAssertEqual([CDRUpdatePreferences preferencesFromDefaults:self.defaults].shownTypes,
                   CDRReleaseNoteTypeSetAll);
}

#pragma mark - Interest scheme

- (void)testChoosingAPresetSeedsTheShownCategories {
    CDRMutableUpdatePreferences *m = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    m.interestScheme = CDRInterestSchemeEverything;
    XCTAssertEqual(m.shownTypes, CDRReleaseNoteTypeSetAll);
    XCTAssertFalse(m.exposesDeveloperDetail);

    m.interestScheme = CDRInterestSchemeDeveloper;
    XCTAssertEqual(m.shownTypes, CDRReleaseNoteTypeSetAll);
    XCTAssertTrue(m.exposesDeveloperDetail);

    m.interestScheme = CDRInterestSchemeNormal;
    XCTAssertFalse(CDRReleaseNoteTypeSetContains(m.shownTypes, CDRReleaseNoteTypeSecurity));
    XCTAssertTrue(CDRReleaseNoteTypeSetContains(m.shownTypes, CDRReleaseNoteTypeFixed));
}

- (void)testEditingACategoryAfterAPresetLeavesNoPresetSelected {
    CDRMutableUpdatePreferences *m = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    m.interestScheme = CDRInterestSchemeDeveloper;
    m.shownTypes = m.shownTypes & ~CDRReleaseNoteTypeSetFixed;
    XCTAssertEqual(m.interestScheme, CDRInterestSchemeCustom);
    XCTAssertFalse(m.exposesDeveloperDetail);
    XCTAssertFalse(CDRReleaseNoteTypeSetContains(m.shownTypes, CDRReleaseNoteTypeFixed));

    // …and choosing a preset again discards the hand edit.
    m.interestScheme = CDRInterestSchemeEverything;
    XCTAssertEqual(m.shownTypes, CDRReleaseNoteTypeSetAll);
}

- (void)testSchemeTokensRoundTrip {
    for (NSNumber *n in @[@(CDRInterestSchemeNormal), @(CDRInterestSchemeEverything),
                          @(CDRInterestSchemeDeveloper), @(CDRInterestSchemeCustom)]) {
        CDRInterestScheme scheme = (CDRInterestScheme)n.integerValue;
        XCTAssertEqual(CDRInterestSchemeFromDefaultsToken(CDRInterestSchemeDefaultsToken(scheme)), scheme);
    }
    XCTAssertEqual(CDRInterestSchemeFromDefaultsToken(@"power user"), CDRInterestSchemeNormal);
    XCTAssertEqual(CDRInterestSchemeFromDefaultsToken(nil), CDRInterestSchemeNormal);
}

#pragma mark - Resolver

- (CDRUpdatePreferences *)globalThreeDays {
    CDRMutableUpdatePreferences *m = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    m.soakDuration = CDRSoakDurationThreeDays;
    return [m copy];
}

- (void)testResolverWithNoOverrideReturnsTheGlobalValues {
    CDRUpdatePreferences *global = [self globalThreeDays];
    XCTAssertEqualObjects([CDRPolicyResolver effectivePreferencesWithGlobal:global override:nil], global);
    XCTAssertEqualObjects([CDRPolicyResolver effectivePreferencesWithGlobal:global
                                                                  override:[[CDRAppPolicyOverride alloc] init]],
                          global);
}

- (void)testResolverWithAPartialOverrideChangesOnlyThatField {
    CDRUpdatePreferences *global = [self globalThreeDays];
    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.soakDuration = @(CDRSoakDurationOneWeek);

    CDRUpdatePreferences *effective = [CDRPolicyResolver effectivePreferencesWithGlobal:global override:override];
    XCTAssertEqual(effective.soakDuration, CDRSoakDurationOneWeek);
    XCTAssertEqual(effective.stopAtMajorVersions, global.stopAtMajorVersions);
    XCTAssertEqual(effective.shownTypes, global.shownTypes);
    XCTAssertEqual(effective.holdTypes, global.holdTypes);
    XCTAssertEqual(effective.interestScheme, global.interestScheme);
    XCTAssertEqual(effective.requireNetworkApproval, global.requireNetworkApproval);

    // An override can also switch a deferral OFF for one app.
    override.soakDuration = @(CDRSoakDurationOff);
    XCTAssertEqual([CDRPolicyResolver effectivePreferencesWithGlobal:global override:override].soakDuration,
                   CDRSoakDurationOff);
}

- (void)testResolverWithAFullOverride {
    CDRMutableUpdatePreferences *m = [[self globalThreeDays] mutableCopy];
    m.interestScheme = CDRInterestSchemeDeveloper;
    CDRUpdatePreferences *global = [m copy];

    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.soakDuration = @(CDRSoakDurationOff);
    override.stopAtMajorVersions = @YES;
    override.shownTypes = @(CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetSecurity);
    override.holdTypes = @(CDRReleaseNoteTypeSetSecurity);

    CDRUpdatePreferences *effective = [CDRPolicyResolver effectivePreferencesWithGlobal:global override:override];
    XCTAssertEqual(effective.soakDuration, CDRSoakDurationOff);
    XCTAssertTrue(effective.stopAtMajorVersions);
    XCTAssertEqual(effective.shownTypes, CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetSecurity
                   | CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqual(effective.holdTypes, CDRReleaseNoteTypeSetSecurity | CDRReleaseNoteTypeSetRetracted);
    // The scheme (and so Developer detail) stays the user's, not the app's.
    XCTAssertEqual(effective.interestScheme, CDRInterestSchemeDeveloper);
    XCTAssertTrue(effective.exposesDeveloperDetail);
    // The network gate has no per-app override.
    XCTAssertEqual(effective.requireNetworkApproval, global.requireNetworkApproval);
    XCTAssertEqual(effective.policyExemptsApproval, global.policyExemptsApproval);
}

- (void)testResolverWithGarbageStoredOverrideFollowsSettings {
    [[self globalThreeDays] writeToDefaults:self.defaults];
    CDRUpdatePreferences *global = [CDRUpdatePreferences preferencesFromDefaults:self.defaults];

    for (id garbage in @[@"not a dictionary", @[@"a"], @{@"com.example.app": @"nope"},
                         @{@"com.example.app": @{@"defer": @"fortnight", @"stop_at_major": @"yes",
                                                 @"shown": @"everything", @"hold": @7, @"extra": @YES}}]) {
        [self.defaults setObject:garbage forKey:CDRAppPolicyOverridesDefaultsKey];
        XCTAssertTrue(CDRAppPolicyOverrideForBundleID(@"com.example.app", self.defaults).isEmpty);
        XCTAssertEqualObjects([CDRPolicyResolver effectivePreferencesForBundleID:@"com.example.app"
                                                                        defaults:self.defaults], global);
    }
}

#pragma mark - Override storage

- (void)testOverrideRoundTripsAndResetRemovesItEntirely {
    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.soakDuration = @(CDRSoakDurationOneWeek);
    override.shownTypes = @(CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetFixed);
    CDRSetAppPolicyOverride(override, @"com.example.muwav", self.defaults);

    CDRAppPolicyOverride *read = CDRAppPolicyOverrideForBundleID(@"com.example.muwav", self.defaults);
    XCTAssertFalse(read.isEmpty);
    XCTAssertEqualObjects(read.soakDuration, @(CDRSoakDurationOneWeek));
    XCTAssertEqualObjects(read.shownTypes, @(CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetFixed));
    XCTAssertNil(read.holdTypes);
    XCTAssertNil(read.stopAtMajorVersions);
    // Another app is unaffected.
    XCTAssertTrue(CDRAppPolicyOverrideForBundleID(@"com.example.other", self.defaults).isEmpty);

    XCTAssertEqual([CDRPolicyResolver effectivePreferencesForBundleID:@"com.example.muwav"
                                                             defaults:self.defaults].soakDuration,
                   CDRSoakDurationOneWeek);

    // Reset to Settings: the entry is gone, not left behind empty.
    CDRSetAppPolicyOverride(nil, @"com.example.muwav", self.defaults);
    XCTAssertTrue(CDRAppPolicyOverrideForBundleID(@"com.example.muwav", self.defaults).isEmpty);
    XCTAssertNil([self.defaults objectForKey:CDRAppPolicyOverridesDefaultsKey]);

    // Storing an override with nothing in it is the same as resetting.
    CDRSetAppPolicyOverride([[CDRAppPolicyOverride alloc] init], @"com.example.muwav", self.defaults);
    XCTAssertNil([self.defaults objectForKey:CDRAppPolicyOverridesDefaultsKey]);
}

- (void)testOverridesAreNotUpdateMemory {
    // They live in NSUserDefaults (like the ignore list), not in the update
    // state store, so the store's 90-day retention never drops them.
    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    override.stopAtMajorVersions = @NO;
    CDRSetAppPolicyOverride(override, @"com.example.app", self.defaults);
    NSDictionary *stored = [self.defaults dictionaryForKey:CDRAppPolicyOverridesDefaultsKey];
    XCTAssertEqualObjects(stored, (@{@"com.example.app": @{@"stop_at_major": @NO}}));
}

#pragma mark - Wording

- (void)testShownCategoriesSummaryLine {
    CDRReleaseNoteTypeSet global = CDRShownTypesForInterestScheme(CDRInterestSchemeNormal);
    CDRReleaseNoteTypeSet custom = (global | CDRReleaseNoteTypeSetSecurity) & ~CDRReleaseNoteTypeSetFixed;
    // The Settings design's own example.
    XCTAssertEqualObjects(CDRTypeSetOverrideSummary(global, custom, @"shown", @"hidden", @"muwav"),
                          @"Security shown and Fixed hidden for muwav only");
    XCTAssertEqualObjects(CDRTypeSetOverrideSummary(global, global | CDRReleaseNoteTypeSetSecurity,
                                                    @"shown", @"hidden", @"muwav"),
                          @"Security shown for muwav only");
    XCTAssertEqualObjects(CDRTypeSetOverrideSummary(global, global & ~(CDRReleaseNoteTypeSetAdded | CDRReleaseNoteTypeSetFixed),
                                                    @"shown", @"hidden", @"muwav"),
                          @"Added, Fixed hidden for muwav only");
    XCTAssertEqualObjects(CDRTypeSetOverrideSummary(global, global, @"shown", @"hidden", @"muwav"),
                          @"Same as Settings");
    // Retracted is always in both, so leaving it out is not a difference.
    XCTAssertEqualObjects(CDRTypeSetOverrideSummary(global, global & ~CDRReleaseNoteTypeSetRetracted,
                                                    @"shown", @"hidden", @"muwav"),
                          @"Same as Settings");
    XCTAssertEqualObjects(CDRTypeSetOverrideSummary(CDRDefaultHoldTypes, CDRDefaultHoldTypes | CDRReleaseNoteTypeSetSecurity,
                                                    @"held", @"not held", @"muwav"),
                          @"Security held for muwav only");
}

- (void)testSettingsEchoLines {
    XCTAssertEqualObjects(CDRSettingsEchoForSoakDuration(CDRSoakDurationThreeDays), @"Settings: 3 days");
    XCTAssertEqualObjects(CDRSettingsEchoForSoakDuration(CDRSoakDurationOff), @"Settings: off");
    XCTAssertEqualObjects(CDRSettingsEchoForBool(NO), @"Settings: off");
    XCTAssertEqualObjects(CDRSettingsEchoForBool(YES), @"Settings: on");
    XCTAssertEqualObjects(CDRSettingsEchoForTypeSet(CDRDefaultHoldTypes), @"Settings: Notice, Removed, Retracted");
}

@end
