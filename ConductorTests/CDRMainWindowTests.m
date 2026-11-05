//
//  CDRMainWindowTests.m
//  ConductorTests
//
//  The main window's pure pieces (sections, wording, primary action, search)
//  and a render pass that draws every pane in both appearances. The renders
//  are written to disk so they can be laid beside ref-assets/; the
//  assertions here only prove each pane lays out and follows the appearance.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "CDRAppListViewController.h"
#import "CDRAppRowModel_Private.h"
#import "CDRDetailViewController.h"
#import "CDRDevModeSession.h"
#import "CDRInterruptSheetModel.h"
#import "CDRMainWindowController.h"
#import "CDRPalette.h"
#import "CDRRowFixtures.h"
#import "CDRViews.h"
#import "CDRWindowCopy.h"

@interface CDRMainWindowTests : XCTestCase
@end

@implementation CDRMainWindowTests

#pragma mark - Sections

- (void)testEveryStateBelongsToExactlyOneSection {
    NSDictionary<NSNumber *, NSNumber *> *expected = @{
        @(CDRAppRowStateNeedsNetworkApproval): @(CDRAppRowSectionNeedsYou),
        @(CDRAppRowStateHeld): @(CDRAppRowSectionNeedsYou),
        @(CDRAppRowStateStoppedAtMajor): @(CDRAppRowSectionNeedsYou),
        @(CDRAppRowStateRetracted): @(CDRAppRowSectionNeedsYou),
        @(CDRAppRowStateRecalled): @(CDRAppRowSectionNeedsYou),
        @(CDRAppRowStateAvailable): @(CDRAppRowSectionUpdates),
        @(CDRAppRowStateDeferred): @(CDRAppRowSectionUpdates),
        @(CDRAppRowStateInspecting): @(CDRAppRowSectionUpdates),
        @(CDRAppRowStateWorking): @(CDRAppRowSectionUpdates),
        @(CDRAppRowStateWaitingForQuit): @(CDRAppRowSectionUpdates),
        @(CDRAppRowStateUpToDate): @(CDRAppRowSectionUpToDate),
        @(CDRAppRowStateUnknown): @(CDRAppRowSectionNotChecked),
        @(CDRAppRowStateCheckFailed): @(CDRAppRowSectionNotChecked),
        @(CDRAppRowStateIgnored): @(CDRAppRowSectionNotChecked),
    };
    // Every state is listed above: a state added later must be placed here.
    XCTAssertEqual(expected.count, (NSUInteger)(CDRAppRowStateNeedsNetworkApproval + 1));
    [expected enumerateKeysAndObjectsUsingBlock:^(NSNumber *state, NSNumber *section, BOOL *stop) {
        XCTAssertEqual(CDRAppRowSectionForState((CDRAppRowState)state.integerValue),
                       (CDRAppRowSection)section.integerValue, @"state %@", state);
    }];
    // Only a row Conductor has actually checked is ever called "up to date".
    XCTAssertEqualObjects(CDRAppRowSectionTitle(CDRAppRowSectionUpToDate), @"UP TO DATE");
    XCTAssertNotEqual(CDRAppRowSectionForState(CDRAppRowStateCheckFailed), CDRAppRowSectionUpToDate);
    XCTAssertNotEqual(CDRAppRowSectionForState(CDRAppRowStateUnknown), CDRAppRowSectionUpToDate);
}

- (void)testListGroupsRowsBySectionInDisplayOrder {
    NSArray *items = [CDRAppListViewController listItemsForRowModels:[CDRRowFixtures designRows] query:nil];
    NSMutableArray<NSString *> *flat = [NSMutableArray array];
    for (id item in items) {
        [flat addObject:[item isKindOfClass:[NSNumber class]]
            ? CDRAppRowSectionTitle((CDRAppRowSection)[item integerValue])
            : ((CDRAppRowModel *)item).appName];
    }
    XCTAssertEqualObjects(flat, (@[
        @"NEEDS YOU", @"Van-cast", @"SmoothMove", @"Fastmail SSB", @"Swift Unxip",
        @"UPDATES", @"muwav", @"Understudy", @"xkcd Adopted",
        @"UP TO DATE", @"Fakear",
    ]));
}

- (void)testSearchFiltersByAppNameAndDropsEmptySections {
    NSArray<CDRAppRowModel *> *rows = [CDRRowFixtures designRows];
    NSArray *items = [CDRAppListViewController listItemsForRowModels:rows query:@"  MU "];
    XCTAssertEqual(items.count, 2u);
    XCTAssertEqualObjects(items[0], @(CDRAppRowSectionUpdates));
    XCTAssertEqualObjects(((CDRAppRowModel *)items[1]).appName, @"muwav");

    // Case- and diacritic-insensitive, substring.
    items = [CDRAppListViewController listItemsForRowModels:rows query:@"ädopt"];
    XCTAssertEqualObjects(((CDRAppRowModel *)items.lastObject).appName, @"xkcd Adopted");

    XCTAssertEqual([CDRAppListViewController listItemsForRowModels:rows query:@"zzz"].count, 0u);
    XCTAssertEqual([CDRAppListViewController listItemsForRowModels:rows query:@""].count, 11u);
}

#pragma mark - Wording

- (void)testWindowSummaryCountsUpdatesAndNeedsYou {
    NSArray<CDRAppRowModel *> *rows = [CDRRowFixtures designRows];
    // 4 need you (the ticket files StoppedAtMajor there) + 3 updates.
    XCTAssertEqualObjects(CDRWindowSummary(rows), @"7 updates · 4 need you");

    CDRAppRowModel *available = [CDRRowFixtures designRowNamed:@"muwav"];
    CDRAppRowModel *held = [CDRRowFixtures designRowNamed:@"SmoothMove"];
    CDRAppRowModel *current = [CDRRowFixtures designRowNamed:@"Fakear"];
    XCTAssertEqualObjects(CDRWindowSummary(@[available, current]), @"1 update");
    XCTAssertEqualObjects(CDRWindowSummary(@[held, current]), @"1 update · 1 needs you");
    XCTAssertEqualObjects(CDRWindowSummary(@[current]), @"No updates");
    XCTAssertEqualObjects(CDRWindowSummary(@[]), @"");
}

- (void)testCheckedAgo {
    NSDate *now = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
    XCTAssertEqualObjects(CDRCheckedAgoString(nil, now), @"Not checked yet");
    XCTAssertEqualObjects(CDRCheckedAgoString([now dateByAddingTimeInterval:-20], now), @"Checked just now");
    XCTAssertEqualObjects(CDRCheckedAgoString([now dateByAddingTimeInterval:-4 * 60 - 30], now), @"Checked 4 min ago");
    XCTAssertEqualObjects(CDRCheckedAgoString([now dateByAddingTimeInterval:-2 * 3600 - 5], now), @"Checked 2 hr ago");
    XCTAssertEqualObjects(CDRCheckedAgoString([now dateByAddingTimeInterval:-30 * 3600], now), @"Checked yesterday");
    XCTAssertEqualObjects(CDRCheckedAgoString([now dateByAddingTimeInterval:-3 * 86400 - 5], now), @"Checked 3 days ago");
}

- (void)testShortStateLinesMatchTheDesign {
    NSDate *now = [NSDate date];
    NSDictionary<NSString *, NSString *> *expected = @{
        @"Van-cast": @"Approve network access",
        @"SmoothMove": @"Held · includes a removal",
        @"Fastmail SSB": @"1.2 was retracted",
        @"muwav": @"Update available",
        @"Understudy": @"Inspecting…",
        @"xkcd Adopted": @"Deferred · 2 days left",
        @"Swift Unxip": @"Stopped at major version",
        @"Fakear": @"Up to date",
    };
    for (CDRAppRowModel *row in [CDRRowFixtures designRows]) {
        XCTAssertEqualObjects([row shortStateLineAsOf:now], expected[row.appName], @"%@", row.appName);
        XCTAssertGreaterThan(row.stateSymbolName.length, 0u);
        XCTAssertNotNil([NSImage imageWithSystemSymbolName:row.stateSymbolName accessibilityDescription:nil],
                        @"%@ is not an SF Symbol", row.stateSymbolName);
        XCTAssertFalse([[row shortStateLineAsOf:now].lowercaseString containsString:@"soak"]);
    }
}

- (void)testHeldLineNamesTheFirstHeldTypeInFixedOrder {
    CDRAppRowModel *row = [CDRRowFixtures designRowNamed:@"SmoothMove"];
    row.heldTypes = CDRReleaseNoteTypeSetFixed | CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetRemoved;
    XCTAssertEqualObjects([row shortStateLineAsOf:[NSDate date]], @"Held · includes a notice");
    row.heldTypes = CDRReleaseNoteTypeSetNone;
    XCTAssertEqualObjects([row shortStateLineAsOf:[NSDate date]], @"Held for manual install");
}

- (void)testDeferredLineCountsDaysLeft {
    CDRAppRowModel *row = [CDRRowFixtures designRowNamed:@"xkcd Adopted"];
    NSDate *now = [NSDate dateWithTimeIntervalSinceReferenceDate:800000000];
    row.deferredUntil = [now dateByAddingTimeInterval:6.5 * 86400];
    XCTAssertEqualObjects([row shortStateLineAsOf:now], @"Deferred · 7 days left");
    row.deferredUntil = [now dateByAddingTimeInterval:86400];
    XCTAssertEqualObjects([row shortStateLineAsOf:now], @"Deferred · 1 day left");
    row.deferredUntil = [now dateByAddingTimeInterval:3 * 3600];
    XCTAssertEqualObjects([row shortStateLineAsOf:now], @"Deferred · less than a day left");
    row.deferredUntil = [now dateByAddingTimeInterval:-60];
    XCTAssertEqualObjects([row shortStateLineAsOf:now], @"Deferred");
}

#pragma mark - Dots, versions, includes

- (void)testCategoryDotsAndVersionPair {
    CDRAppRowModel *muwav = [CDRRowFixtures designRowNamed:@"muwav"];
    XCTAssertEqualObjects(muwav.versionPairDisplay, @"1.2 → 1.4");
    XCTAssertEqual(muwav.noteTypes, CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetRemoved
                   | CDRReleaseNoteTypeSetSecurity | CDRReleaseNoteTypeSetAdded
                   | CDRReleaseNoteTypeSetImproved | CDRReleaseNoteTypeSetFixed);
    XCTAssertEqualObjects(muwav.includedVersions, (@[@"1.3"]));
    XCTAssertEqual(muwav.releases.count, 2u);
    XCTAssertEqual(muwav.releases[1].typeSet, CDRReleaseNoteTypeSetDisabled | CDRReleaseNoteTypeSetAdded
                   | CDRReleaseNoteTypeSetImproved | CDRReleaseNoteTypeSetFixed);

    CDRAppRowModel *fastmail = [CDRRowFixtures designRowNamed:@"Fastmail SSB"];
    XCTAssertEqual(fastmail.noteTypes, CDRReleaseNoteTypeSetRetracted);
    XCTAssertEqualObjects(fastmail.versionPairDisplay, @"1.1");
    XCTAssertEqual(fastmail.includedVersions.count, 0u);

    CDRCategoryDotsView *dots = [[CDRCategoryDotsView alloc] initWithTypes:muwav.noteTypes];
    XCTAssertEqualObjects(dots.accessibilityLabel, @"Notice, Removed, Security, Added, Improved, Fixed");
}

#pragma mark - Selection and the primary action

- (void)testDefaultSelectionIsTheFirstRowThatNeedsReading {
    NSArray<CDRAppRowModel *> *rows = [CDRRowFixtures designRows];
    XCTAssertEqualObjects(CDRDefaultSelection(rows).appName, @"Van-cast");

    CDRAppRowModel *available = [CDRRowFixtures designRowNamed:@"muwav"];
    CDRAppRowModel *current = [CDRRowFixtures designRowNamed:@"Fakear"];
    XCTAssertEqualObjects(CDRDefaultSelection(@[current, available]).appName, @"muwav");
    XCTAssertNil(CDRDefaultSelection(@[current]), @"nothing to read: the pane says so instead");
    XCTAssertTrue(CDRAllRowsUpToDate(@[current]));
    XCTAssertFalse(CDRAllRowsUpToDate(@[current, available]));
    XCTAssertFalse(CDRAllRowsUpToDate(@[]));
}

- (void)testPrimaryActionMapping {
    NSDictionary<NSString *, NSArray *> *expected = @{
        @"muwav": @[@"Update to 1.4", @(CDRAppRowActionInstall)],
        @"SmoothMove": @[@"Install 1.4", @(CDRAppRowActionInstall)],
        @"Van-cast": @[@"Approve…", @(CDRAppRowActionInstall)],
        @"Fakear": @[@"Check now", @(CDRAppRowActionCheckNow)],
    };
    for (CDRAppRowModel *row in [CDRRowFixtures designRows]) {
        NSString *title = @"unset";
        CDRAppRowActions action = CDRPrimaryActionForRow(row, &title);
        NSArray *want = expected[row.appName];
        if (want) {
            XCTAssertEqualObjects(title, want[0], @"%@", row.appName);
            XCTAssertEqual(action, (CDRAppRowActions)[want[1] unsignedIntegerValue]);
        } else {
            // Deferred, retracted, inspecting and major-stop panes carry
            // their own buttons.
            XCTAssertNil(title, @"%@", row.appName);
            XCTAssertEqual(action, CDRAppRowActionNone);
        }
    }
}

- (void)testPrimaryActionIsNeverOfferedWhenTheRowCannotPerformIt {
    CDRAppRowModel *row = [CDRRowFixtures designRowNamed:@"muwav"];
    row.actions = CDRAppRowActionCheckNow;   // Install withheld
    NSString *title = @"unset";
    XCTAssertEqual(CDRPrimaryActionForRow(row, &title), CDRAppRowActionNone);
    XCTAssertNil(title);
}

#pragma mark - Render

- (NSURL *)renderDirectory {
    NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"CDRRenders"
                                                                                 isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    return dir;
}

/// Draws the window's content into a bitmap and writes it as a PNG.
- (NSBitmapImageRep *)renderWindow:(NSWindow *)window named:(NSString *)name {
    NSView *view = window.contentView;
    [view layoutSubtreeIfNeeded];
    [view display];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSURL *url = [[self renderDirectory] URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    XCTAssertTrue([png writeToURL:url atomically:YES], @"could not write %@", url.path);
    return rep;
}

/// Asserts the rendered pixel at a fraction of the bitmap's size is `hex`
/// (0xRRGGBB). Reads the bitmap's own bytes — the same values the written
/// PNG holds — so no color-space conversion sits between the draw and the check.
- (void)assertPixelIn:(NSBitmapImageRep *)rep atX:(double)fx y:(double)fy isHex:(NSUInteger)hex {
    NSUInteger pixel[5] = {0, 0, 0, 0, 0};
    [rep getPixel:pixel atX:(NSInteger)(rep.pixelsWide * fx) y:(NSInteger)(rep.pixelsHigh * fy)];
    NSUInteger actual = (pixel[0] << 16) | (pixel[1] << 8) | pixel[2];
    XCTAssertEqual(actual, hex, @"pixel (%.2f, %.2f) is #%06lX, expected #%06lX",
                   fx, fy, (unsigned long)actual, (unsigned long)hex);
}

/// The design rows as a "Normal user" sees them: Security collapsed.
- (NSArray<CDRAppRowModel *> *)designRowsHidingSecurity {
    NSArray<CDRAppRowModel *> *rows = [CDRRowFixtures designRows];
    for (CDRAppRowModel *row in rows) {
        row.shownTypes = CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetSecurity;
    }
    return rows;
}

- (CDRMainWindowController *)windowWithRows:(NSArray<CDRAppRowModel *> *)rows {
    CDRDevModeSession *session = [CDRDevModeSession sessionFromArguments:@[@"conductor"] error:NULL];
    XCTAssertNotNil(session);
    CDRMainWindowController *controller = [[CDRMainWindowController alloc] initWithSession:session];
    [controller.window setFrame:NSMakeRect(0, 0, 1280, 820) display:NO];
    controller.lastCheckDate = [NSDate dateWithTimeIntervalSinceNow:-4 * 60];
    controller.rowModels = rows;
    return controller;
}

- (void)testMainWindowRendersInBothAppearances {
    // The design's default: Security collapses to a one-line count.
    CDRMainWindowController *controller = [self windowWithRows:[self designRowsHidingSecurity]];
    controller.selectedBundleID = [CDRRowFixtures designRowNamed:@"muwav"].bundleID;

    controller.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSBitmapImageRep *light = [self renderWindow:controller.window named:@"main-light"];
    controller.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSBitmapImageRep *dark = [self renderWindow:controller.window named:@"main-dark"];

    // Bottom-right is empty detail surface, bottom-left is empty sidebar:
    // both must be the design's colors in each appearance.
    [self assertPixelIn:light atX:0.97 y:0.97 isHex:0xFFFFFF];
    [self assertPixelIn:dark atX:0.97 y:0.97 isHex:0x1E1E21];
    [self assertPixelIn:light atX:0.02 y:0.97 isHex:0xF1F1F4];
    [self assertPixelIn:dark atX:0.02 y:0.97 isHex:0x232326];
}

- (void)testEveryPaneLaysOutInBothAppearances {
    NSArray<CDRAppRowModel *> *rows = [CDRRowFixtures designRows];
    NSMutableArray<CDRAppRowModel *> *all = [rows mutableCopy];
    // States the design's main window doesn't show but the app can reach.
    NSArray<NSArray *> *extra = @[
        @[@"Recalled App", @(CDRAppRowStateRecalled)], @[@"Failing App", @(CDRAppRowStateCheckFailed)],
        @[@"Ignored App", @(CDRAppRowStateIgnored)], @[@"Unchecked App", @(CDRAppRowStateUnknown)],
        @[@"Parked App", @(CDRAppRowStateWaitingForQuit)], @[@"Working App", @(CDRAppRowStateWorking)],
    ];
    for (NSArray *entry in extra) {
        CDRAppRowState state = (CDRAppRowState)[entry[1] integerValue];
        BOOL updating = (state == CDRAppRowStateWaitingForQuit || state == CDRAppRowStateWorking);
        CDRAppRowModel *row = [CDRRowFixtures rowNamed:entry[0] state:state installed:@"2.0"
                                            advertised:updating ? @"2.1" : nil
                                                 notes:updating ? @[@[@"fixed", @"A fix."]] : nil history:nil];
        if (state == CDRAppRowStateRecalled) row.retractedVersion = @"2.0";
        if (state == CDRAppRowStateWorking) row.operationPhase = CDRUpdatePhaseVerifying;
        [all addObject:row];
    }

    CDRMainWindowController *controller = [self windowWithRows:all];
    for (NSString *appearanceName in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        controller.window.appearance = [NSAppearance appearanceNamed:appearanceName];
        NSString *suffix = [appearanceName isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
        for (CDRAppRowModel *row in all) {
            controller.selectedBundleID = row.bundleID;
            XCTAssertEqualObjects(controller.detailViewController.rowModel.bundleID, row.bundleID);
            NSString *slug = [[row.appName lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"-"];
            NSBitmapImageRep *rep = [self renderWindow:controller.window
                                                 named:[NSString stringWithFormat:@"pane-%@-%@", slug, suffix]];
            XCTAssertGreaterThan(rep.pixelsWide, 0);
        }
    }
}

- (void)testNoSelectionPanes {
    // No apps at all.
    CDRMainWindowController *empty = [self windowWithRows:@[]];
    XCTAssertNil(empty.selectedBundleID);
    [self renderWindow:empty.window named:@"pane-no-apps-light"];

    // Everything up to date: nothing is selected, the pane says so.
    CDRAppRowModel *a = [CDRRowFixtures rowNamed:@"Fakear" state:CDRAppRowStateUpToDate installed:@"1.0.3"
                                      advertised:nil notes:nil history:nil];
    CDRAppRowModel *b = [CDRRowFixtures rowNamed:@"muwav" state:CDRAppRowStateUpToDate installed:@"1.4"
                                      advertised:nil notes:nil history:nil];
    CDRMainWindowController *current = [self windowWithRows:@[a, b]];
    XCTAssertNil(current.selectedBundleID);
    XCTAssertNil(current.detailViewController.rowModel);
    [self renderWindow:current.window named:@"pane-all-up-to-date-light"];
    current.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [self renderWindow:current.window named:@"pane-all-up-to-date-dark"];

    // An update arriving selects it; the user's own choice then sticks.
    CDRAppRowModel *update = [CDRRowFixtures designRowNamed:@"muwav"];
    current.rowModels = @[a, update];
    XCTAssertEqualObjects(current.selectedBundleID, update.bundleID);
    current.selectedBundleID = a.bundleID;
    current.rowModels = @[a, update];
    XCTAssertEqualObjects(current.selectedBundleID, a.bundleID);
    // …until that app goes away.
    current.rowModels = @[update];
    XCTAssertEqualObjects(current.selectedBundleID, update.bundleID);
}

- (void)testSkippedVersionExpandsAndHiddenCategoryReveals {
    CDRMainWindowController *controller = [self windowWithRows:[self designRowsHidingSecurity]];
    CDRAppRowModel *muwav = [CDRRowFixtures designRowNamed:@"muwav"];
    controller.selectedBundleID = muwav.bundleID;
    CDRDetailViewController *detail = controller.detailViewController;

    // Collapsed: the 1.3 row's notes and the security items are not drawn.
    XCTAssertFalse([self view:detail.view containsText:@"Lower memory use during playback."]);
    XCTAssertFalse([self view:detail.view containsText:@"Artwork downloads now verify the server certificate."]);
    XCTAssertTrue([self view:detail.view containsText:@"2 security fixes hidden  ·"]);
    XCTAssertTrue([self view:detail.view containsText:@"Includes 1.3"]);
    XCTAssertTrue([self view:detail.view containsText:@"4 notes"]);

    NSButton *show = [self buttonIn:detail.view withIdentifierSuffix:@"|1.4|security"];
    XCTAssertNotNil(show);
    [show performClick:nil];
    XCTAssertTrue([self view:detail.view containsText:@"Artwork downloads now verify the server certificate."]);

    NSButton *toggle = [self buttonIn:detail.view withIdentifierSuffix:@"|1.3"];
    XCTAssertNotNil(toggle);
    [toggle performClick:nil];
    XCTAssertTrue([self view:detail.view containsText:@"Lower memory use during playback."]);
    [self renderWindow:controller.window named:@"main-expanded-light"];

    // Both survive a refresh of the same rows.
    controller.rowModels = [self designRowsHidingSecurity];
    XCTAssertTrue([self view:detail.view containsText:@"Lower memory use during playback."]);
    XCTAssertTrue([self view:detail.view containsText:@"Artwork downloads now verify the server certificate."]);
}

- (void)testDetailButtonsSendTheRowAction {
    CDRMainWindowController *controller = [self windowWithRows:[CDRRowFixtures designRows]];
    __block NSString *sentBundleID = nil;
    __block CDRAppRowActions sentAction = CDRAppRowActionNone;
    controller.onRowAction = ^(NSString *bundleID, CDRAppRowActions action) {
        sentBundleID = bundleID;
        sentAction = action;
    };

    CDRAppRowModel *muwav = [CDRRowFixtures designRowNamed:@"muwav"];
    controller.selectedBundleID = muwav.bundleID;
    [[self buttonIn:controller.detailViewController.view withTitle:@"Update to 1.4"] performClick:nil];
    XCTAssertEqualObjects(sentBundleID, muwav.bundleID);
    XCTAssertEqual(sentAction, CDRAppRowActionInstall);

    CDRAppRowModel *fastmail = [CDRRowFixtures designRowNamed:@"Fastmail SSB"];
    controller.selectedBundleID = fastmail.bundleID;
    [[self buttonIn:controller.detailViewController.view withTitle:@"Got it"] performClick:nil];
    XCTAssertEqualObjects(sentBundleID, fastmail.bundleID);
    XCTAssertEqual(sentAction, CDRAppRowActionAcknowledge);

    // The deferred pane: "Update now" is the break-through consent, and
    // "Keep waiting" sends nothing at all.
    CDRAppRowModel *xkcd = [CDRRowFixtures designRowNamed:@"xkcd Adopted"];
    controller.selectedBundleID = xkcd.bundleID;
    XCTAssertTrue([self view:controller.detailViewController.view
                containsText:@"You wait 3 days before new builds show up."]);
    sentAction = CDRAppRowActionNone;
    [[self buttonIn:controller.detailViewController.view withTitle:@"Keep waiting"] performClick:nil];
    XCTAssertEqual(sentAction, CDRAppRowActionNone);
    [[self buttonIn:controller.detailViewController.view withTitle:@"Update now"] performClick:nil];
    XCTAssertEqualObjects(sentBundleID, xkcd.bundleID);
    XCTAssertEqual(sentAction, CDRAppRowActionInstallDeferred);

    // The major-stop pane's two buttons.
    CDRAppRowModel *unxip = [CDRRowFixtures designRowNamed:@"Swift Unxip"];
    controller.selectedBundleID = unxip.bundleID;
    [[self buttonIn:controller.detailViewController.view withTitle:@"Always allow for this app"] performClick:nil];
    XCTAssertEqual(sentAction, CDRAppRowActionAlwaysAllowMajor);
    [[self buttonIn:controller.detailViewController.view withTitle:@"Install 1.0"] performClick:nil];
    XCTAssertEqualObjects(sentBundleID, unxip.bundleID);
    XCTAssertEqual(sentAction, CDRAppRowActionInstall);

    // The per-app override button is disabled until the window is told
    // where overrides are stored.
    controller.selectedBundleID = muwav.bundleID;
    NSButton *override = nil;
    for (NSButton *button in [self buttonsIn:controller.detailViewController.view]) {
        if ([button.accessibilityLabel isEqualToString:@"Settings for this app"]) override = button;
    }
    XCTAssertNotNil(override);
    XCTAssertFalse(override.isEnabled);
}

#pragma mark - Interrupt sheets

- (void)testASheetIsNotDroppedFromAWindowThatIsNotOnScreen {
    // Sheets are for a user who is looking at the window. Off screen, the
    // caller is told "dismiss" at once and nothing is attached.
    CDRMainWindowController *controller = [self windowWithRows:[CDRRowFixtures designRows]];
    XCTAssertFalse(controller.window.isVisible);
    XCTAssertFalse(controller.canPresentInterruptSheet);

    CDRInterruptSheetModel *model = [CDRInterruptSheetModel retractionModelForAppNamed:@"Fastmail SSB" appURL:nil
                                                                      retractedVersion:@"1.2" installedVersion:@"1.1"];
    __block NSInteger reported = -1;
    [controller presentInterruptSheet:model completion:^(NSInteger action, BOOL usedLink) {
        reported = action;
        XCTAssertFalse(usedLink);
    }];
    XCTAssertEqual(reported, CDRInterruptSheetActionDismiss);
    XCTAssertNil(controller.window.attachedSheet);
}

- (void)testTheRetractionPaneGivesTheDatesWhenTheyAreKnown {
    CDRAppRowModel *fastmail = [CDRRowFixtures designRowNamed:@"Fastmail SSB"];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2026; c.month = 11; c.day = 1; c.hour = 12;
    fastmail.retractionAdvertisedDate = [calendar dateFromComponents:c];
    c.day = 2;
    fastmail.retractionPulledDate = [calendar dateFromComponents:c];
    CDRMainWindowController *controller = [self windowWithRows:@[fastmail]];
    controller.selectedBundleID = fastmail.bundleID;
    XCTAssertTrue([self view:controller.detailViewController.view
                containsText:@"1.2 was advertised on Nov 1 and pulled on Nov 2. There's nothing to install."]);
}

#pragma mark - View helpers

- (NSArray<NSView *> *)descendantsOf:(NSView *)view {
    NSMutableArray<NSView *> *all = [NSMutableArray array];
    for (NSView *sub in view.subviews) {
        if (sub.isHidden) continue;
        [all addObject:sub];
        [all addObjectsFromArray:[self descendantsOf:sub]];
    }
    return all;
}

- (BOOL)view:(NSView *)view containsText:(NSString *)text {
    for (NSView *sub in [self descendantsOf:view]) {
        if ([sub isKindOfClass:[NSTextField class]] && [((NSTextField *)sub).stringValue containsString:text]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSButton *> *)buttonsIn:(NSView *)view {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSView *sub in [self descendantsOf:view]) {
        if ([sub isKindOfClass:[NSButton class]]) [buttons addObject:(NSButton *)sub];
    }
    return buttons;
}

- (nullable NSButton *)buttonIn:(NSView *)view withTitle:(NSString *)title {
    for (NSButton *button in [self buttonsIn:view]) {
        if ([button.title isEqualToString:title]) return button;
    }
    return nil;
}

- (nullable NSButton *)buttonIn:(NSView *)view withIdentifierSuffix:(NSString *)suffix {
    for (NSButton *button in [self buttonsIn:view]) {
        if ([button.identifier hasSuffix:suffix]) return button;
    }
    return nil;
}

@end
