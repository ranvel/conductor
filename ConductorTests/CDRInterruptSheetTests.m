//
//  CDRInterruptSheetTests.m
//  ConductorTests
//
//  The interrupt sheet: the pure model (wording, which button is default,
//  what each response means) and a smoke pass that lays out all four
//  variants in both appearances and drives their buttons.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "CDRInterruptSheetController.h"
#import "CDRInterruptSheetModel.h"
#import "CDRManifest.h"

@interface CDRInterruptSheetTests : XCTestCase
@end

@implementation CDRInterruptSheetTests

#pragma mark - Fixtures (the four sheets of ref-assets/Interrupt sheets)

- (NSURL *)iconURL {
    return [NSURL fileURLWithPath:@"/System/Applications/Utilities/Terminal.app"];
}

- (NSArray<CDRRelease *> *)releasesWithNotes:(NSArray<NSArray<NSString *> *> *)pairs {
    NSMutableArray *notes = [NSMutableArray array];
    for (NSArray<NSString *> *pair in pairs) [notes addObject:@{@"type": pair[0], @"text": pair[1]}];
    CDRManifest *manifest = [CDRManifest manifestWithData:[NSJSONSerialization dataWithJSONObject:@{
        @"conductor_manifest": @1, @"bundle_id": @"com.example.app", @"version": @"1.4",
        @"url": @"https://example.com/app.dmg", @"notes": notes,
        @"history": @[@{@"version": @"1.3.5", @"notes": @[@{@"type": @"notice", @"text": @"A skipped notice."},
                                                          @{@"type": @"fixed", @"text": @"A skipped fix."}]}],
    } options:0 error:NULL] error:NULL];
    return [manifest releasesNewerThanVersion:@"1.3"];
}

- (CDRInterruptSheetModel *)heldModel {
    NSArray<CDRRelease *> *releases = [self releasesWithNotes:@[
        @[@"fixed", @"Windows keep their size across Spaces."],
        @[@"removed", @"Snap-resistance override for external displays. macOS now handles this itself."],
    ]];
    CDRReleaseNoteTypeSet hold = CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetRemoved;
    return [CDRInterruptSheetModel heldModelForAppNamed:@"SmoothMove" appURL:[self iconURL] version:@"1.4"
                                             heldGroups:CDRNoteGroupsOfTypes(releases, hold) holdTypes:hold];
}

- (CDRInterruptSheetModel *)retractionModel {
    return [CDRInterruptSheetModel retractionModelForAppNamed:@"Fastmail SSB" appURL:[self iconURL]
                                             retractedVersion:@"1.2" installedVersion:@"1.1"];
}

- (NSArray<CDRInterruptSheetDiffLine *> *)clientDiff {
    return @[[CDRInterruptSheetDiffLine lineWithText:@"com.apple.security.network.client" added:YES]];
}

- (CDRInterruptSheetModel *)networkPolicyModel {
    return [CDRInterruptSheetModel networkModelForAppNamed:@"Van-cast" appURL:[self iconURL]
                                               fromVersion:@"0.4" toVersion:@"0.5" diffLines:[self clientDiff]
                                                policyRows:@[
        [CDRInterruptSheetPolicyRow rowWithSubject:@"Any feed you add"
                                           purpose:@"Checks your subscriptions for new episodes and downloads them."],
        [CDRInterruptSheetPolicyRow rowWithSubject:@"search.example.com"
                                           purpose:@"Podcast directory search, only when you type in Search."],
    ]];
}

- (CDRInterruptSheetModel *)networkNoPolicyModel {
    return [CDRInterruptSheetModel networkModelForAppNamed:@"Understudy" appURL:[self iconURL]
                                               fromVersion:@"0.8" toVersion:@"0.9" diffLines:[self clientDiff]
                                                policyRows:nil];
}

#pragma mark - Model

- (void)testHeldSheetWording {
    CDRInterruptSheetModel *model = [self heldModel];
    XCTAssertEqual(model.kind, CDRInterruptSheetKindHeld);
    XCTAssertEqualObjects(model.title, @"SmoothMove 1.4 is waiting for you");
    XCTAssertFalse(model.attentionHeader);
    XCTAssertEqualObjects(model.footnote, @"You hold updates that include Notice, Removed or Retracted items.");
    XCTAssertEqualObjects(model.linkTitle, @"Change in Settings");
    XCTAssertNil(model.diffLines);
    XCTAssertNil(model.policyRows);
    XCTAssertNil(model.warning);
}

- (void)testHeldSheetShowsOnlyTheOffendingNotesFromEveryReleaseBeingTaken {
    CDRInterruptSheetModel *model = [self heldModel];
    // The skipped 1.3.5's notice and 1.4's removal — in the fixed order,
    // and not the fixes.
    XCTAssertEqualObjects([model.noteGroups valueForKey:@"type"],
                          (@[@(CDRReleaseNoteTypeNotice), @(CDRReleaseNoteTypeRemoved)]));
    XCTAssertEqualObjects(model.noteGroups[0].notes.firstObject.text, @"A skipped notice.");
    XCTAssertEqual(model.noteGroups[1].notes.count, 1u);
    // The subtitle names the first held category in that order.
    XCTAssertEqualObjects(model.subtitle, @"Held because it includes a notice.");
}

- (void)testTheSafeChoiceIsAlwaysTheDefaultButton {
    // Held: the user opened it — Install.
    CDRInterruptSheetModel *held = [self heldModel];
    XCTAssertEqualObjects(held.defaultButton.title, @"Install 1.4");
    XCTAssertEqual(held.defaultButton.action, CDRInterruptSheetActionInstall);
    XCTAssertEqualObjects(held.secondaryButton.title, @"Not now");
    XCTAssertEqual(held.secondaryButton.action, CDRInterruptSheetActionDismiss);

    // Retraction: one button, OK.
    CDRInterruptSheetModel *retraction = [self retractionModel];
    XCTAssertEqualObjects(retraction.defaultButton.title, @"OK");
    XCTAssertNil(retraction.secondaryButton);

    // A policy is present: Approve.
    CDRInterruptSheetModel *policy = [self networkPolicyModel];
    XCTAssertEqualObjects(policy.defaultButton.title, @"Approve and update");
    XCTAssertEqual(policy.defaultButton.action, CDRInterruptSheetActionInstall);
    XCTAssertEqualObjects(policy.secondaryButton.title, @"Skip this version");
    XCTAssertEqual(policy.secondaryButton.action, CDRInterruptSheetActionSkipVersion);

    // No policy: Skip.
    CDRInterruptSheetModel *noPolicy = [self networkNoPolicyModel];
    XCTAssertEqualObjects(noPolicy.defaultButton.title, @"Skip this version");
    XCTAssertEqual(noPolicy.defaultButton.action, CDRInterruptSheetActionSkipVersion);
    XCTAssertEqualObjects(noPolicy.secondaryButton.title, @"Approve anyway");
    XCTAssertEqual(noPolicy.secondaryButton.action, CDRInterruptSheetActionInstall);
}

- (void)testResponsesMapToActions {
    CDRInterruptSheetModel *noPolicy = [self networkNoPolicyModel];
    XCTAssertEqual([noPolicy actionForResponse:CDRInterruptSheetResponseDefault], CDRInterruptSheetActionSkipVersion);
    XCTAssertEqual([noPolicy actionForResponse:CDRInterruptSheetResponseSecondary], CDRInterruptSheetActionInstall);

    CDRInterruptSheetModel *held = [self heldModel];
    XCTAssertEqual([held actionForResponse:CDRInterruptSheetResponseDefault], CDRInterruptSheetActionInstall);
    XCTAssertEqual([held actionForResponse:CDRInterruptSheetResponseSecondary], CDRInterruptSheetActionDismiss);
    // The link never installs.
    XCTAssertEqual([held actionForResponse:CDRInterruptSheetResponseLink], CDRInterruptSheetActionDismiss);

    // Escape on the one-button retraction sheet is that button.
    CDRInterruptSheetModel *retraction = [self retractionModel];
    XCTAssertEqual([retraction actionForResponse:CDRInterruptSheetResponseSecondary], CDRInterruptSheetActionDismiss);
}

- (void)testRetractionSheetWording {
    CDRInterruptSheetModel *model = [self retractionModel];
    XCTAssertEqual(model.kind, CDRInterruptSheetKindRetraction);
    XCTAssertTrue(model.attentionHeader);
    XCTAssertEqualObjects(model.title, @"Developer retracted 1.2");
    XCTAssertEqualObjects(model.subtitle, @"You have the latest build.");
    XCTAssertEqualObjects(model.body,
        @"Fastmail SSB 1.2 was advertised, then pulled. 1.1 stays installed and nothing changes on your Mac.");
    XCTAssertEqualObjects(model.bodyEmphasis, @"Fastmail SSB");
    XCTAssertNil(model.noteGroups);
}

- (void)testNetworkSheetWording {
    CDRInterruptSheetModel *policy = [self networkPolicyModel];
    XCTAssertEqual(policy.kind, CDRInterruptSheetKindNetworkWithPolicy);
    XCTAssertEqualObjects(policy.title, @"Van-cast 0.5 adds internet access");
    XCTAssertEqualObjects(policy.subtitle, @"0.4 made no connections.");
    XCTAssertEqualObjects(policy.diffHeading, @"ENTITLEMENTS · 0.4 → 0.5");
    XCTAssertEqual(policy.policyRows.count, 2u);
    XCTAssertNil(policy.warning);

    CDRInterruptSheetModel *noPolicy = [self networkNoPolicyModel];
    XCTAssertEqual(noPolicy.kind, CDRInterruptSheetKindNetworkNoPolicy);
    XCTAssertEqualObjects(noPolicy.title, @"Understudy 0.9 wants internet access and doesn’t say why.");
    XCTAssertEqualObjects(noPolicy.warning, @"This build ships no Internet Access Policy.");
    XCTAssertNil(noPolicy.policyRows);

    // An empty policy is no policy.
    CDRInterruptSheetModel *empty = [CDRInterruptSheetModel networkModelForAppNamed:@"A" appURL:nil fromVersion:@"1"
                                                                          toVersion:@"2" diffLines:[self clientDiff]
                                                                         policyRows:@[]];
    XCTAssertEqual(empty.kind, CDRInterruptSheetKindNetworkNoPolicy);
}

- (void)testOrList {
    XCTAssertEqualObjects(CDRReleaseNoteTypeSetOrList(CDRReleaseNoteTypeSetRetracted), @"Retracted");
    XCTAssertEqualObjects(CDRReleaseNoteTypeSetOrList(CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetRetracted),
                          @"Notice or Retracted");
    XCTAssertEqualObjects(CDRReleaseNoteTypeSetOrList(CDRReleaseNoteTypeSetNone), @"");
}

#pragma mark - Component

- (NSArray<NSView *> *)descendantsOf:(NSView *)view {
    NSMutableArray<NSView *> *all = [NSMutableArray array];
    for (NSView *sub in view.subviews) {
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

- (void)render:(NSView *)view named:(NSString *)name {
    [view layoutSubtreeIfNeeded];
    [view display];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"CDRRenders"
                                                                                 isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    XCTAssertTrue([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToURL:[dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]] atomically:YES]);
}

- (void)testEveryVariantLaysOutInBothAppearances {
    NSDictionary<NSString *, CDRInterruptSheetModel *> *models = @{
        @"held": [self heldModel], @"retraction": [self retractionModel],
        @"network-policy": [self networkPolicyModel], @"network-no-policy": [self networkNoPolicyModel],
    };
    [models enumerateKeysAndObjectsUsingBlock:^(NSString *name, CDRInterruptSheetModel *model, BOOL *stop) {
        CDRInterruptSheetController *sheet = [[CDRInterruptSheetController alloc] initWithModel:model];
        NSView *content = sheet.window.contentView;
        XCTAssertEqual(NSWidth(content.frame), 520, @"%@", name);
        XCTAssertGreaterThan(NSHeight(content.frame), 120, @"%@ has no height", name);
        XCTAssertFalse(content.hasAmbiguousLayout, @"%@", name);
        XCTAssertTrue([self view:content containsText:model.title], @"%@", name);

        // Return is the default button; Escape the secondary one.
        NSButton *defaultButton = [self viewIn:content withIdentifier:@"sheet.default"];
        XCTAssertEqualObjects(defaultButton.title, model.defaultButton.title);
        XCTAssertEqualObjects(defaultButton.keyEquivalent, @"\r");
        NSButton *secondary = [self viewIn:content withIdentifier:@"sheet.secondary"];
        if (model.secondaryButton) {
            XCTAssertEqualObjects(secondary.title, model.secondaryButton.title);
            XCTAssertEqualObjects(secondary.keyEquivalent, @"\033");
        } else {
            XCTAssertNil(secondary);
        }

        sheet.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [self render:content named:[NSString stringWithFormat:@"sheet-%@-light", name]];
        sheet.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        [self render:content named:[NSString stringWithFormat:@"sheet-%@-dark", name]];
    }];
}

- (void)testOptionalSectionsAppearOnlyWhenTheModelCarriesThem {
    NSView *held = [[CDRInterruptSheetController alloc] initWithModel:[self heldModel]].window.contentView;
    XCTAssertTrue([self view:held containsText:@"Snap-resistance override for external displays."]);
    XCTAssertTrue([self view:held containsText:@"You hold updates that include"]);
    XCTAssertNotNil([self viewIn:held withIdentifier:@"sheet.link"]);
    XCTAssertFalse([self view:held containsText:@"ENTITLEMENTS"]);
    XCTAssertFalse([self view:held containsText:@"Internet Access Policy"]);

    NSView *policy = [[CDRInterruptSheetController alloc] initWithModel:[self networkPolicyModel]].window.contentView;
    XCTAssertTrue([self view:policy containsText:@"+ com.apple.security.network.client"]);
    XCTAssertTrue([self view:policy containsText:@"Internet Access Policy"]);
    XCTAssertTrue([self view:policy containsText:@"search.example.com"]);
    XCTAssertTrue([self view:policy containsText:@"Podcast directory search, only when you type in Search."]);
    XCTAssertNil([self viewIn:policy withIdentifier:@"sheet.link"]);

    NSView *noPolicy = [[CDRInterruptSheetController alloc] initWithModel:[self networkNoPolicyModel]].window.contentView;
    XCTAssertTrue([self view:noPolicy containsText:@"This build ships no Internet Access Policy."]);
    XCTAssertFalse([self view:noPolicy containsText:@"from the developer"]);

    NSView *retraction = [[CDRInterruptSheetController alloc] initWithModel:[self retractionModel]].window.contentView;
    XCTAssertTrue([self view:retraction containsText:@"You have the latest build."]);
    XCTAssertTrue([self view:retraction containsText:@"1.1 stays installed"]);
}

- (void)testButtonsReportTheirResponseOnce {
    for (NSArray *expectation in @[@[@"sheet.default", @(CDRInterruptSheetResponseDefault)],
                                   @[@"sheet.secondary", @(CDRInterruptSheetResponseSecondary)],
                                   @[@"sheet.link", @(CDRInterruptSheetResponseLink)]]) {
        CDRInterruptSheetController *sheet = [[CDRInterruptSheetController alloc] initWithModel:[self heldModel]];
        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:YES];
        __block NSMutableArray<NSNumber *> *responses = [NSMutableArray array];
        XCTestExpectation *done = [self expectationWithDescription:expectation[0]];
        [sheet beginSheetOnWindow:parent completion:^(CDRInterruptSheetResponse response) {
            [responses addObject:@(response)];
            [done fulfill];
        }];
        // (The parent is never ordered on screen in a test, so AppKit queues
        // the sheet rather than attaching it; the response path is the same.)
        [(NSButton *)[self viewIn:sheet.window.contentView withIdentifier:expectation[0]] performClick:nil];
        [self waitForExpectations:@[done] timeout:5];
        XCTAssertEqualObjects(responses, (@[expectation[1]]));
    }
}

@end
