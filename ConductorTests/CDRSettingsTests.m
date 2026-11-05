//
//  CDRSettingsTests.m
//  ConductorTests
//
//  The Settings form and the per-app override popover, driven through their
//  real controls against a throwaway defaults suite. Renders are written to
//  $TMPDIR/CDRRenders for comparison with ref-assets/.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "CDRSettingsWindowController+Testing.h"
#import "CDROverridePopoverController.h"
#import "CDRScanScheduler.h"
#import "CDRUpdatePreferences.h"

@interface CDRSettingsTests : XCTestCase
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic, copy) NSString *suiteName;
@end

@implementation CDRSettingsTests

- (void)setUp {
    self.suiteName = [NSString stringWithFormat:@"cdr-settings-tests-%@", NSUUID.UUID.UUIDString];
    self.defaults = [[NSUserDefaults alloc] initWithSuiteName:self.suiteName];
}

- (void)tearDown {
    [self.defaults removePersistentDomainForName:self.suiteName];
}

#pragma mark - Helpers

- (CDRUpdatePreferences *)stored {
    return [CDRUpdatePreferences preferencesFromDefaults:self.defaults];
}

- (void)choose:(NSInteger)segment in:(NSSegmentedControl *)control {
    control.selectedSegment = segment;
    [NSApp sendAction:control.action to:control.target from:control];
}

- (void)render:(NSView *)view named:(NSString *)name {
    [view layoutSubtreeIfNeeded];
    [view display];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"CDRRenders"
                                                                                 isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    XCTAssertTrue([png writeToURL:[dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]
                       atomically:YES]);
}

- (NSArray<NSView *> *)descendantsOf:(NSView *)view {
    NSMutableArray<NSView *> *all = [NSMutableArray array];
    for (NSView *sub in view.subviews) {
        if (sub.isHidden) continue;
        [all addObject:sub];
        [all addObjectsFromArray:[self descendantsOf:sub]];
    }
    return all;
}

- (nullable __kindof NSView *)viewIn:(NSView *)root withIdentifier:(NSString *)identifier {
    for (NSView *view in [self descendantsOf:root]) {
        if ([view.identifier isEqualToString:identifier]) return view;
    }
    return nil;
}

- (BOOL)view:(NSView *)root containsText:(NSString *)text {
    for (NSView *view in [self descendantsOf:root]) {
        if ([view isKindOfClass:[NSTextField class]] && [((NSTextField *)view).stringValue containsString:text]) {
            return YES;
        }
    }
    return NO;
}

- (NSUInteger)overriddenTagCountIn:(NSView *)root {
    NSUInteger count = 0;
    for (NSView *view in [self descendantsOf:root]) {
        if ([view.identifier hasPrefix:@"overridden."]) count++;
    }
    return count;
}

#pragma mark - Settings form

- (void)testFreshSettingsShowTheDefaults {
    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];

    XCTAssertEqual(settings.deferralControl.segmentCount, 4);
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) [labels addObject:[settings.deferralControl labelForSegment:i]];
    XCTAssertEqualObjects(labels, (@[@"Off", @"1 day", @"3 days", @"1 week"]));
    XCTAssertEqual(settings.deferralControl.selectedSegment, 0);
    XCTAssertEqual(settings.stopAtMajorSwitch.state, NSControlStateValueOff);

    // Normal user: only Security unchecked.
    XCTAssertEqualObjects([settings.schemeCards valueForKey:@"selected"], (@[@YES, @NO, @NO]));
    XCTAssertEqual(settings.shownGrid.selectedTypes, CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetSecurity);
    XCTAssertEqual([settings.shownGrid checkboxForType:CDRReleaseNoteTypeSecurity].state, NSControlStateValueOff);
    XCTAssertEqual([settings.shownGrid checkboxForType:CDRReleaseNoteTypeFixed].state, NSControlStateValueOn);

    XCTAssertEqual(settings.holdGrid.selectedTypes, CDRDefaultHoldTypes);
    XCTAssertEqual(settings.requireApprovalSwitch.state, NSControlStateValueOn);
    XCTAssertEqual(settings.policyExemptsSwitch.state, NSControlStateValueOn);
    XCTAssertTrue(settings.policyExemptsSwitch.isEnabled);

    // Showing the defaults writes nothing.
    XCTAssertNil([self.defaults objectForKey:CDRInterestSchemeDefaultsKey]);
}

- (void)testEveryControlRoundTripsThroughARelaunch {
    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];
    __block NSUInteger changes = 0;
    settings.onPreferencesChanged = ^{ changes++; };

    [self choose:2 in:settings.deferralControl];                 // 3 days
    [settings.stopAtMajorSwitch performClick:nil];               // on
    [[settings.schemeCards[2] valueForKey:@"button"] performClick:nil];   // Developer
    [[settings.holdGrid checkboxForType:CDRReleaseNoteTypeSecurity] performClick:nil];   // + Security
    [[settings.holdGrid checkboxForType:CDRReleaseNoteTypeNotice] performClick:nil];     // − Notice
    [settings.policyExemptsSwitch performClick:nil];             // off
    XCTAssertEqual(changes, 6u);

    XCTAssertEqualObjects([self.defaults stringForKey:CDRSoakDurationDefaultsKey], @"3d");
    CDRUpdatePreferences *stored = [self stored];
    XCTAssertEqual(stored.soakDuration, CDRSoakDurationThreeDays);
    XCTAssertTrue(stored.stopAtMajorVersions);
    XCTAssertEqual(stored.interestScheme, CDRInterestSchemeDeveloper);
    XCTAssertEqual(stored.holdTypes, CDRReleaseNoteTypeSetRemoved | CDRReleaseNoteTypeSetSecurity
                   | CDRReleaseNoteTypeSetRetracted);
    XCTAssertTrue(stored.requireNetworkApproval);
    XCTAssertFalse(stored.policyExemptsApproval);

    // "Quit and relaunch": a new window over the same defaults.
    CDRSettingsWindowController *relaunched = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];
    XCTAssertEqual(relaunched.deferralControl.selectedSegment, 2);
    XCTAssertEqual(relaunched.stopAtMajorSwitch.state, NSControlStateValueOn);
    XCTAssertEqualObjects([relaunched.schemeCards valueForKey:@"selected"], (@[@NO, @NO, @YES]));
    XCTAssertEqual(relaunched.shownGrid.selectedTypes, CDRReleaseNoteTypeSetAll);
    XCTAssertEqual(relaunched.holdGrid.selectedTypes, stored.holdTypes);
    XCTAssertEqual(relaunched.policyExemptsSwitch.state, NSControlStateValueOff);
}

- (void)testChoosingASchemeSetsTheGridAndEditingItDeselectsThePresets {
    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];

    [[settings.schemeCards[1] valueForKey:@"button"] performClick:nil];   // Everything
    XCTAssertEqualObjects([settings.schemeCards valueForKey:@"selected"], (@[@NO, @YES, @NO]));
    XCTAssertEqual([settings.shownGrid checkboxForType:CDRReleaseNoteTypeSecurity].state, NSControlStateValueOn);
    XCTAssertEqual([self stored].shownTypes, CDRReleaseNoteTypeSetAll);

    // Editing a checkbox afterwards: no preset stays selected.
    [[settings.shownGrid checkboxForType:CDRReleaseNoteTypeFixed] performClick:nil];
    XCTAssertEqualObjects([settings.schemeCards valueForKey:@"selected"], (@[@NO, @NO, @NO]));
    XCTAssertEqual([self stored].interestScheme, CDRInterestSchemeCustom);
    XCTAssertEqual([self stored].shownTypes, CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetFixed);

    // Choosing a preset again takes over the grid.
    [[settings.schemeCards[0] valueForKey:@"button"] performClick:nil];   // Normal user
    XCTAssertEqualObjects([settings.schemeCards valueForKey:@"selected"], (@[@YES, @NO, @NO]));
    XCTAssertEqual([settings.shownGrid checkboxForType:CDRReleaseNoteTypeFixed].state, NSControlStateValueOn);
    XCTAssertEqual([settings.shownGrid checkboxForType:CDRReleaseNoteTypeSecurity].state, NSControlStateValueOff);
}

- (void)testRetractedIsCheckedAndDisabledInBothGridsWhateverIsStored {
    // As if by `defaults write`: Retracted left out of both sets.
    [self.defaults setObject:@"custom" forKey:CDRInterestSchemeDefaultsKey];
    [self.defaults setObject:@[@"added"] forKey:CDRShownNoteTypesDefaultsKey];
    [self.defaults setObject:@[] forKey:CDRHoldNoteTypesDefaultsKey];

    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];
    for (CDRCategoryGridView *grid in @[settings.shownGrid, settings.holdGrid]) {
        NSButton *retracted = [grid checkboxForType:CDRReleaseNoteTypeRetracted];
        XCTAssertNotNil(retracted);
        XCTAssertEqual(retracted.state, NSControlStateValueOn);
        XCTAssertFalse(retracted.isEnabled);
        // Clicking it does nothing.
        [retracted performClick:nil];
        XCTAssertEqual(retracted.state, NSControlStateValueOn);
        XCTAssertTrue(CDRReleaseNoteTypeSetContains(grid.selectedTypes, CDRReleaseNoteTypeRetracted));
    }
    // Other boxes still work, and what gets written keeps Retracted.
    [[settings.holdGrid checkboxForType:CDRReleaseNoteTypeRemoved] performClick:nil];
    XCTAssertEqual([self stored].holdTypes, CDRReleaseNoteTypeSetRemoved | CDRReleaseNoteTypeSetRetracted);
    XCTAssertTrue([[self.defaults arrayForKey:CDRHoldNoteTypesDefaultsKey] containsObject:@"retracted"]);
}

- (void)testInternetAccessPolicyExemptionIsDisabledWhileApprovalIsOff {
    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];
    XCTAssertTrue(settings.policyExemptsSwitch.isEnabled);

    [settings.requireApprovalSwitch performClick:nil];   // off
    XCTAssertFalse([self stored].requireNetworkApproval);
    XCTAssertFalse(settings.policyExemptsSwitch.isEnabled);
    // The nested value itself is kept for when approval comes back on.
    XCTAssertTrue([self stored].policyExemptsApproval);

    [settings.requireApprovalSwitch performClick:nil];   // on again
    XCTAssertTrue(settings.policyExemptsSwitch.isEnabled);
    XCTAssertEqual(settings.policyExemptsSwitch.state, NSControlStateValueOn);
}

- (void)testExistingControlsAndKeysAreUntouched {
    [self.defaults setObject:@"1w" forKey:CDRSoakDurationDefaultsKey];
    [self.defaults setObject:@"6h" forKey:CDRScanCadenceDefaultsKey];
    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];
    // A value stored before v2 shows on the new control…
    XCTAssertEqual(settings.deferralControl.selectedSegment, 3);
    XCTAssertEqualObjects(settings.cadencePopup.titleOfSelectedItem, @"Every 6 hours");

    // …and changing an unrelated setting doesn't disturb it.
    [settings.stopAtMajorSwitch performClick:nil];
    XCTAssertEqualObjects([self.defaults stringForKey:CDRSoakDurationDefaultsKey], @"1w");
    XCTAssertEqualObjects([self.defaults stringForKey:CDRScanCadenceDefaultsKey], @"6h");
}

- (void)testSettingsRenderInBothAppearancesAndScrollToASection {
    CDRSettingsWindowController *settings = [[CDRSettingsWindowController alloc] initWithDefaults:self.defaults];
    [self choose:2 in:settings.deferralControl];
    [settings.window setContentSize:NSMakeSize(640, 860)];
    settings.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [self render:settings.window.contentView named:@"settings-light"];
    settings.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [self render:settings.window.contentView named:@"settings-dark"];

    // In a short window, "Change in Settings" can land on the hold group.
    [settings.window setContentSize:NSMakeSize(640, 380)];
    [settings.window.contentView layoutSubtreeIfNeeded];
    XCTAssertEqual(settings.scrollView.contentView.bounds.origin.y, 0);
    [settings showSection:CDRSettingsSectionInstallManually];
    XCTAssertGreaterThan(settings.scrollView.contentView.bounds.origin.y, 200);
    settings.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [self render:settings.window.contentView named:@"settings-install-manually-light"];
}

#pragma mark - Per-app popover

- (CDROverridePopoverController *)popover {
    CDROverridePopoverController *popover =
        [[CDROverridePopoverController alloc] initWithBundleID:@"com.example.muwav" appName:@"muwav"
                                                        appURL:[NSURL fileURLWithPath:@"/System/Applications/Utilities/Terminal.app"]
                                                      defaults:self.defaults];
    [popover view];
    return popover;
}

- (void)testPopoverFollowsSettingsEverywhereForAnAppWithNoOverride {
    CDRMutableUpdatePreferences *global = [[self stored] mutableCopy];
    global.soakDuration = CDRSoakDurationThreeDays;
    [global writeToDefaults:self.defaults];

    CDROverridePopoverController *popover = [self popover];
    for (NSString *identifier in @[@"override.defer", @"override.shown", @"override.hold", @"override.major"]) {
        NSSegmentedControl *control = [self viewIn:popover.view withIdentifier:identifier];
        XCTAssertNotNil(control, @"%@", identifier);
        XCTAssertEqual(control.selectedSegment, 0, @"%@ should follow Settings", identifier);
    }
    XCTAssertEqual([self overriddenTagCountIn:popover.view], 0u);
    // The current Settings values are echoed.
    XCTAssertTrue([self view:popover.view containsText:@"Settings: 3 days"]);
    XCTAssertTrue([self view:popover.view containsText:@"Settings: Notice, Removed, Retracted"]);
    XCTAssertTrue([self view:popover.view containsText:@"Settings: off"]);
    XCTAssertFalse(((NSButton *)[self viewIn:popover.view withIdentifier:@"override.reset"]).isEnabled);
    XCTAssertNil([self viewIn:popover.view withIdentifier:@"override.shown.grid"]);
}

- (void)testChangingOneFieldMarksThatSectionOverriddenAndSummarizesTheDifference {
    CDROverridePopoverController *popover = [self popover];
    __block NSUInteger changes = 0;
    popover.onChanged = ^{ changes++; };

    // Deferral: 1 week for this app while Settings is Off.
    [self choose:2 in:[self viewIn:popover.view withIdentifier:@"override.defer"]];
    XCTAssertEqual([self overriddenTagCountIn:popover.view], 1u);
    XCTAssertNotNil([self viewIn:popover.view withIdentifier:@"overridden.Defer new updates"]);
    XCTAssertEqual([CDRPolicyResolver effectivePreferencesForBundleID:@"com.example.muwav"
                                                             defaults:self.defaults].soakDuration,
                   CDRSoakDurationOneWeek);
    XCTAssertEqual([self stored].soakDuration, CDRSoakDurationOff, @"Settings itself is untouched");

    // Shown categories → Custom starts from Settings, so nothing differs yet.
    [self choose:1 in:[self viewIn:popover.view withIdentifier:@"override.shown"]];
    CDRCategoryGridView *grid = [self viewIn:popover.view withIdentifier:@"override.shown.grid"];
    XCTAssertNotNil(grid);
    XCTAssertNil([grid checkboxForType:CDRReleaseNoteTypeRetracted], @"the popover grid has no Retracted cell");
    XCTAssertTrue([self view:popover.view containsText:@"Same as Settings"]);

    // The design's example: Security shown and Fixed hidden.
    [[grid checkboxForType:CDRReleaseNoteTypeSecurity] performClick:nil];
    grid = [self viewIn:popover.view withIdentifier:@"override.shown.grid"];
    [[grid checkboxForType:CDRReleaseNoteTypeFixed] performClick:nil];
    XCTAssertTrue([self view:popover.view containsText:@"Security shown and Fixed hidden for muwav only"]);
    XCTAssertEqual([self overriddenTagCountIn:popover.view], 2u);
    XCTAssertEqual(changes, 4u);

    CDRUpdatePreferences *effective = [CDRPolicyResolver effectivePreferencesForBundleID:@"com.example.muwav"
                                                                                defaults:self.defaults];
    XCTAssertTrue(CDRReleaseNoteTypeSetContains(effective.shownTypes, CDRReleaseNoteTypeSecurity));
    XCTAssertFalse(CDRReleaseNoteTypeSetContains(effective.shownTypes, CDRReleaseNoteTypeFixed));
    // Another app still follows Settings.
    XCTAssertEqualObjects([CDRPolicyResolver effectivePreferencesForBundleID:@"com.example.other"
                                                                    defaults:self.defaults], [self stored]);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 600)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.contentViewController = popover;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [self render:popover.view named:@"popover-light"];
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [self render:popover.view named:@"popover-dark"];
}

- (void)testResetToSettingsRemovesTheOverrideAndTheTags {
    CDROverridePopoverController *popover = [self popover];
    [self choose:1 in:[self viewIn:popover.view withIdentifier:@"override.major"]];   // On
    [self choose:1 in:[self viewIn:popover.view withIdentifier:@"override.hold"]];    // Custom
    XCTAssertEqual([self overriddenTagCountIn:popover.view], 2u);
    XCTAssertNotNil([self.defaults objectForKey:CDRAppPolicyOverridesDefaultsKey]);

    __block NSUInteger changes = 0;
    popover.onChanged = ^{ changes++; };
    NSButton *reset = [self viewIn:popover.view withIdentifier:@"override.reset"];
    XCTAssertTrue(reset.isEnabled);
    [reset performClick:nil];

    XCTAssertEqual(changes, 1u);
    XCTAssertNil([self.defaults objectForKey:CDRAppPolicyOverridesDefaultsKey]);
    XCTAssertEqual([self overriddenTagCountIn:popover.view], 0u);
    for (NSString *identifier in @[@"override.defer", @"override.shown", @"override.hold", @"override.major"]) {
        XCTAssertEqual(((NSSegmentedControl *)[self viewIn:popover.view withIdentifier:identifier]).selectedSegment, 0);
    }
}

- (void)testStopAtMajorOverrideOffersOnAndOff {
    CDROverridePopoverController *popover = [self popover];
    [self choose:1 in:[self viewIn:popover.view withIdentifier:@"override.major"]];
    XCTAssertTrue([CDRPolicyResolver effectivePreferencesForBundleID:@"com.example.muwav"
                                                            defaults:self.defaults].stopAtMajorVersions);
    [self choose:2 in:[self viewIn:popover.view withIdentifier:@"override.major"]];
    XCTAssertEqualObjects(CDRAppPolicyOverrideForBundleID(@"com.example.muwav", self.defaults).stopAtMajorVersions, @NO);
    [self choose:0 in:[self viewIn:popover.view withIdentifier:@"override.major"]];
    XCTAssertTrue(CDRAppPolicyOverrideForBundleID(@"com.example.muwav", self.defaults).isEmpty);
}

@end
