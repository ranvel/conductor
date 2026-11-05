//
//  CDRMainWindowController.m
//  Conductor
//

#import "CDRMainWindowController.h"
#import "CDRAppListViewController.h"
#import "CDRDetailViewController.h"
#import "CDRDevModeSession.h"
#import "CDRInterruptSheetController.h"
#import "CDROverridePopoverController.h"
#import "CDRPalette.h"
#import "CDRViews.h"
#import "CDRWindowCopy.h"

static NSString * const kSplitAutosaveName = @"CDRMainSplit";
static NSString * const kWindowAutosaveName = @"CDRMainWindow";

static NSToolbarItemIdentifier const kTitleItem = @"CDRToolbarTitle";
static NSToolbarItemIdentifier const kCheckedItem = @"CDRToolbarChecked";
static NSToolbarItemIdentifier const kCheckItem = @"CDRToolbarCheckNow";
static NSToolbarItemIdentifier const kSettingsItem = @"CDRToolbarSettings";

/// The split view with the design's hairline between the panes instead of
/// AppKit's default divider color.
@interface CDRMainSplitView : NSSplitView
@end

@implementation CDRMainSplitView
- (NSColor *)dividerColor { return CDRPalette.hairline; }
@end

@interface CDRMainWindowController () <NSToolbarDelegate>
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) NSSplitViewController *splitViewController;
@property (nonatomic) CDRAppListViewController *listViewController;
@property (nonatomic, readwrite) CDRDetailViewController *detailViewController;
@property (nonatomic) NSTextField *titleLabel;
@property (nonatomic) NSTextField *checkedLabel;
@property (nonatomic) CDRButton *checkButton;
@property (nonatomic) NSTimer *clockTimer;
@property (nonatomic, nullable) NSPopover *overridePopover;
/// Held while its sheet is up.
@property (nonatomic, nullable) CDRInterruptSheetController *interruptSheet;
@end

@implementation CDRMainWindowController

- (instancetype)initWithSession:(CDRDevModeSession *)session {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1280, 768)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:YES];
    self = [super initWithWindow:window];
    if (!self) return nil;
    _session = session;
    _rowModels = @[];

    window.title = @"Conductor";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
    window.backgroundColor = CDRPalette.titleBarSurface;
    window.minSize = NSMakeSize(860, 520);
    window.releasedWhenClosed = NO;

    [self buildContent];
    [self buildToolbar];

    // First launch: centered at the design size. After that the frame and
    // the divider position are the user's.
    [window center];
    window.frameAutosaveName = kWindowAutosaveName;
    [self applyDefaultDividerPositionIfNeeded];

    __weak typeof(self) weakSelf = self;
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshTitleBar];
    }];
    self.clockTimer.tolerance = 5;
    [self refreshAll];
    return self;
}

- (void)dealloc {
    [_clockTimer invalidate];
}

#pragma mark - Construction

- (void)buildContent {
    self.listViewController = [[CDRAppListViewController alloc] init];
    self.detailViewController = [[CDRDetailViewController alloc] init];

    __weak typeof(self) weakSelf = self;
    self.listViewController.onSelectionChanged = ^(NSString *bundleID) {
        [weakSelf userSelectedBundleID:bundleID];
    };
    self.listViewController.onRowAction = ^(NSString *bundleID, CDRAppRowActions action) {
        if (weakSelf.onRowAction) weakSelf.onRowAction(bundleID, action);
    };
    self.detailViewController.onRowAction = ^(NSString *bundleID, CDRAppRowActions action) {
        if (weakSelf.onRowAction) weakSelf.onRowAction(bundleID, action);
    };
    self.detailViewController.onCheckAll = ^{
        if (weakSelf.onCheckAll) weakSelf.onCheckAll();
    };
    self.detailViewController.onScanAgain = ^{
        if (weakSelf.onScanAgain) weakSelf.onScanAgain();
    };

    NSSplitViewController *split = [[NSSplitViewController alloc] init];
    split.splitView = [[CDRMainSplitView alloc] initWithFrame:NSZeroRect];
    split.splitView.vertical = YES;
    split.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    NSSplitViewItem *listItem = [NSSplitViewItem splitViewItemWithViewController:self.listViewController];
    listItem.minimumThickness = 240;
    listItem.maximumThickness = 440;
    listItem.canCollapse = NO;
    // The list holds its width; resizing the window grows the reading pane.
    listItem.holdingPriority = NSLayoutPriorityDefaultLow + 10;
    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:self.detailViewController];
    detailItem.minimumThickness = 520;
    detailItem.canCollapse = NO;
    [split addSplitViewItem:listItem];
    [split addSplitViewItem:detailItem];
    split.splitView.autosaveName = kSplitAutosaveName;
    self.splitViewController = split;

    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 768)];
    NSView *splitView = split.view;
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:splitView];

    NSLayoutYAxisAnchor *top = root.topAnchor;
    if (self.session.devModeEnabled) {
        // Dev mode relaxes transport for one app. It must be impossible to
        // miss, on every pane, for the whole session.
        CDRSurfaceView *banner = [CDRSurfaceView surfaceWithFill:NSColor.systemRedColor];
        NSTextField *label = CDRLabel([NSString stringWithFormat:@"DEV MODE — %@ — insecure connections permitted",
                                       self.session.devModeBundleID ?: @""],
                                      [NSFont systemFontOfSize:13 weight:NSFontWeightBold], NSColor.whiteColor, NO);
        [banner addSubview:label];
        [root addSubview:banner];
        [NSLayoutConstraint activateConstraints:@[
            [banner.topAnchor constraintEqualToAnchor:root.topAnchor],
            [banner.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
            [banner.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
            [banner.heightAnchor constraintEqualToConstant:28],
            [label.centerXAnchor constraintEqualToAnchor:banner.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
            [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:banner.leadingAnchor constant:12],
        ]];
        top = banner.bottomAnchor;
    }
    [NSLayoutConstraint activateConstraints:@[
        [splitView.topAnchor constraintEqualToAnchor:top],
        [splitView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.window.contentView = root;
}

/// ≈20% for the list at the default width, unless the user already dragged
/// the divider somewhere (NSSplitView restores that from its autosave).
- (void)applyDefaultDividerPositionIfNeeded {
    NSString *key = [@"NSSplitView Subview Frames " stringByAppendingString:kSplitAutosaveName];
    if ([[NSUserDefaults standardUserDefaults] objectForKey:key]) return;
    [self.window.contentView layoutSubtreeIfNeeded];
    CGFloat width = NSWidth(self.splitViewController.splitView.bounds);
    [self.splitViewController.splitView setPosition:MAX(240, round(width * 0.2)) ofDividerAtIndex:0];
}

- (void)buildToolbar {
    self.titleLabel = CDRLabel(@"Conductor", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                               CDRPalette.textPrimary, NO);
    self.checkedLabel = CDRLabel(@"", [NSFont systemFontOfSize:12], CDRPalette.textSecondary, NO);
    self.checkButton = [CDRButton buttonWithTitle:@"Check now" style:CDRButtonStyleSecondary
                                           target:self action:@selector(checkNowClicked:)];
    self.checkButton.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];

    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"CDRMainToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    toolbar.showsBaselineSeparator = NO;
    self.window.toolbar = toolbar;
    self.window.toolbarStyle = NSWindowToolbarStyleUnified;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[kTitleItem, NSToolbarFlexibleSpaceItemIdentifier, kCheckedItem, kCheckItem, kSettingsItem];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.bordered = NO;
    if ([identifier isEqualToString:kTitleItem]) {
        item.view = self.titleLabel;
        item.label = @"Conductor";
        item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
    } else if ([identifier isEqualToString:kCheckedItem]) {
        item.view = self.checkedLabel;
        item.label = @"Last checked";
        item.visibilityPriority = NSToolbarItemVisibilityPriorityLow;
    } else if ([identifier isEqualToString:kCheckItem]) {
        item.view = self.checkButton;
        item.label = @"Check now";
        item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
    } else if ([identifier isEqualToString:kSettingsItem]) {
        CDRButton *settings = [CDRButton iconButtonWithSymbolName:@"slider.horizontal.3"
                                               accessibilityLabel:@"Settings"
                                                           target:self
                                                           action:@selector(settingsClicked:)];
        item.view = settings;
        item.label = @"Settings";
        item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
    }
    return item;
}

#pragma mark - Inputs

- (void)setRowModels:(NSArray<CDRAppRowModel *> *)rowModels {
    _rowModels = [rowModels copy];
    [self refreshAll];
}

- (void)setLastCheckDate:(NSDate *)lastCheckDate {
    _lastCheckDate = lastCheckDate;
    self.detailViewController.lastCheckDate = lastCheckDate;
    [self refreshTitleBar];
}

- (void)setSelectedBundleID:(NSString *)selectedBundleID {
    _selectedBundleID = [selectedBundleID copy];
    [self refreshAll];
}

- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(NSString *)detail {
    [self.listViewController setProgressActive:active fraction:fraction detail:detail];
    [self.detailViewController setProgressActive:active fraction:fraction detail:detail];
}

- (nullable CDRAppRowModel *)rowForBundleID:(NSString *)bundleID {
    if (!bundleID) return nil;
    for (CDRAppRowModel *row in self.rowModels) {
        if ([row.bundleID isEqualToString:bundleID]) return row;
    }
    return nil;
}

- (void)userSelectedBundleID:(NSString *)bundleID {
    _selectedBundleID = [bundleID copy];
    self.detailViewController.rowModel = [self rowForBundleID:bundleID];
}

- (void)refreshAll {
    // Keep the user's selection while its app exists; otherwise fall back to
    // the first row that needs reading (nil when nothing does).
    CDRAppRowModel *selected = [self rowForBundleID:self.selectedBundleID];
    if (!selected) {
        selected = CDRDefaultSelection(self.rowModels);
        _selectedBundleID = [selected.bundleID copy];
    }
    self.listViewController.rowModels = self.rowModels;
    self.listViewController.selectedBundleID = self.selectedBundleID;
    self.detailViewController.allRowModels = self.rowModels;
    self.detailViewController.rowModel = selected;
    [self refreshTitleBar];
}

- (void)refreshTitleBar {
    NSString *summary = CDRWindowSummary(self.rowModels);
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:@"Conductor" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: CDRPalette.textPrimary,
    }];
    if (summary.length > 0) {
        [title appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@"    " stringByAppendingString:summary] attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:12],
                NSForegroundColorAttributeName: CDRPalette.textSecondary,
            }]];
    }
    self.titleLabel.attributedStringValue = title;
    self.checkedLabel.stringValue = CDRCheckedAgoString(self.lastCheckDate, [NSDate date]);
    self.checkButton.enabled = (self.rowModels.count > 0);
    self.window.title = summary.length > 0 ? [NSString stringWithFormat:@"Conductor — %@", summary] : @"Conductor";
}

#pragma mark - Interrupt sheets

- (BOOL)canPresentInterruptSheet {
    return self.window.isVisible && self.window.attachedSheet == nil && self.interruptSheet == nil;
}

- (void)presentInterruptSheet:(CDRInterruptSheetModel *)model
                   completion:(void (^)(NSInteger, BOOL))completion {
    if (!self.canPresentInterruptSheet) {
        completion(CDRInterruptSheetActionDismiss, NO);
        return;
    }
    [self.overridePopover close];
    CDRInterruptSheetController *sheet = [[CDRInterruptSheetController alloc] initWithModel:model];
    self.interruptSheet = sheet;
    __weak typeof(self) weakSelf = self;
    [sheet beginSheetOnWindow:self.window completion:^(CDRInterruptSheetResponse response) {
        weakSelf.interruptSheet = nil;
        completion([model actionForResponse:response], response == CDRInterruptSheetResponseLink);
    }];
}

#pragma mark - Per-app overrides

- (void)setDefaults:(NSUserDefaults *)defaults {
    _defaults = defaults;
    __weak typeof(self) weakSelf = self;
    self.detailViewController.onShowOverrides = defaults ? ^(NSString *bundleID, NSView *anchor) {
        [weakSelf showOverridesForBundleID:bundleID anchor:anchor];
    } : nil;
}

- (void)showOverridesForBundleID:(NSString *)bundleID anchor:(NSView *)anchor {
    CDRAppRowModel *row = [self rowForBundleID:bundleID];
    if (!row || !self.defaults) return;
    [self.overridePopover close];

    CDROverridePopoverController *content =
        [[CDROverridePopoverController alloc] initWithBundleID:bundleID appName:row.appName
                                                        appURL:row.appURL defaults:self.defaults];
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorSemitransient;
    popover.contentViewController = content;
    __weak typeof(self) weakSelf = self;
    __weak NSPopover *weakPopover = popover;
    content.onChanged = ^{
        // The rows are rebuilt from the new effective preferences; the
        // popover stays open on its own (unchanged) anchor window.
        if (weakSelf.onPreferencesChanged) weakSelf.onPreferencesChanged();
    };
    content.onDone = ^{
        [weakPopover close];
    };
    self.overridePopover = popover;
    // Anchor to the pane, not the button: every change rebuilds the header
    // (and the button with it) while the popover is still open.
    NSView *pane = self.detailViewController.view;
    [popover showRelativeToRect:[anchor convertRect:anchor.bounds toView:pane]
                         ofView:pane
                  preferredEdge:NSRectEdgeMaxY];
}

#pragma mark - Actions

- (void)checkNowClicked:(id)sender {
    if (self.onCheckAll) self.onCheckAll();
}

- (void)settingsClicked:(id)sender {
    if (self.onOpenSettings) self.onOpenSettings();
}

@end
