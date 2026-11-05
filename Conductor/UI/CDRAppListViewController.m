//
//  CDRAppListViewController.m
//  Conductor
//

#import "CDRAppListViewController.h"
#import "CDRPalette.h"
#import "CDRViews.h"

static const CGFloat kRowHeight = 66;
static const CGFloat kHeaderHeight = 34;

#pragma mark - Row view (rounded selection)

@interface CDRAppListRowView : NSTableRowView
@end

@implementation CDRAppListRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    NSRect rect = NSInsetRect(self.bounds, 8, 2);
    [CDRPalette.rowSelection setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:9 yRadius:9] fill];
}

// Keep the design's own ink on the selected row instead of AppKit's
// white-on-accent emphasized style.
- (NSBackgroundStyle)interiorBackgroundStyle { return NSBackgroundStyleNormal; }
- (BOOL)isEmphasized { return NO; }

@end

#pragma mark - Row cell

@interface CDRAppRowCellView : NSTableCellView
@property (nonatomic) NSImageView *iconView;
@property (nonatomic) NSTextField *nameLabel;
@property (nonatomic) NSTextField *versionLabel;
@property (nonatomic) NSImageView *stateGlyph;
@property (nonatomic) NSTextField *stateLabel;
@property (nonatomic) CDRCategoryDotsView *dotsView;
- (void)configureWithModel:(CDRAppRowModel *)model now:(NSDate *)now;
@end

@implementation CDRAppRowCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;

    _nameLabel = CDRLabel(@"", [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold], CDRPalette.textPrimary, NO);
    _versionLabel = CDRLabel(@"", CDRMonoFont(11.5, NSFontWeightRegular), CDRPalette.textSecondary, NO);
    _stateGlyph = CDRSymbolView(@"circle", 10.5, NSFontWeightSemibold, CDRPalette.textSecondary);
    _stateLabel = CDRLabel(@"", [NSFont systemFontOfSize:12 weight:NSFontWeightRegular], CDRPalette.textSecondary, NO);
    _dotsView = [[CDRCategoryDotsView alloc] initWithTypes:CDRReleaseNoteTypeSetNone];

    for (NSView *view in @[_iconView, _nameLabel, _versionLabel, _stateGlyph, _stateLabel, _dotsView]) {
        [self addSubview:view];
    }
    self.textField = _nameLabel;
    self.imageView = _iconView;

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
        [_iconView.widthAnchor constraintEqualToConstant:32],
        [_iconView.heightAnchor constraintEqualToConstant:32],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
        [_nameLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:7],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_dotsView.leadingAnchor constant:-6],

        [_dotsView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_dotsView.centerYAnchor constraintEqualToAnchor:_nameLabel.centerYAnchor],

        [_versionLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_versionLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:1],
        [_versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

        [_stateGlyph.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_stateGlyph.centerYAnchor constraintEqualToAnchor:_stateLabel.centerYAnchor],
        [_stateGlyph.widthAnchor constraintEqualToConstant:13],

        [_stateLabel.leadingAnchor constraintEqualToAnchor:_stateGlyph.trailingAnchor constant:4],
        [_stateLabel.topAnchor constraintEqualToAnchor:_versionLabel.bottomAnchor constant:2],
        [_stateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
    ]];
    return self;
}

- (void)configureWithModel:(CDRAppRowModel *)model now:(NSDate *)now {
    self.iconView.image = [[NSWorkspace sharedWorkspace] iconForFile:model.appURL.path];
    self.nameLabel.stringValue = model.appName;
    self.versionLabel.stringValue = model.versionPairDisplay;
    self.dotsView.types = model.noteTypes;

    NSColor *tone = CDRPalette.textSecondary;
    NSFontWeight weight = NSFontWeightRegular;
    switch (model.stateTone) {
        case CDRAppRowToneAttention: tone = CDRPalette.attentionText; weight = NSFontWeightSemibold; break;
        case CDRAppRowTonePrimary: tone = CDRPalette.textPrimary; weight = NSFontWeightSemibold; break;
        case CDRAppRowToneSecondary: break;
    }
    self.stateLabel.stringValue = [model shortStateLineAsOf:now];
    self.stateLabel.textColor = tone;
    self.stateLabel.font = [NSFont systemFontOfSize:12 weight:weight];
    self.stateGlyph.image = CDRSymbol(model.stateSymbolName, 10.5, NSFontWeightSemibold);
    self.stateGlyph.contentTintColor = tone;

    // An ignored app is still listed, just quieter.
    self.nameLabel.textColor = (model.state == CDRAppRowStateIgnored) ? CDRPalette.textSecondary
                                                                      : CDRPalette.textPrimary;
    self.toolTip = model.stateLine;
}

@end

#pragma mark - List controller

@interface CDRAppListViewController () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate,
                                        NSSearchFieldDelegate>
@property (nonatomic) NSSearchField *searchField;
@property (nonatomic) NSTableView *tableView;
@property (nonatomic) NSTextField *emptyLabel;
@property (nonatomic) NSView *progressContainer;
@property (nonatomic) NSTextField *progressLabel;
@property (nonatomic) CDRProgressBarView *progressBar;
/// The list runs to the bottom of the pane unless the progress line is up.
@property (nonatomic) NSLayoutConstraint *listBottomToPane;
@property (nonatomic) NSLayoutConstraint *listBottomToProgress;
/// NSNumber (section header) or CDRAppRowModel, in display order.
@property (nonatomic, copy) NSArray *items;
@property (nonatomic) BOOL reloading;
@end

@implementation CDRAppListViewController

+ (NSArray *)listItemsForRowModels:(NSArray<CDRAppRowModel *> *)rowModels query:(NSString *)query {
    NSString *needle = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *items = [NSMutableArray array];
    for (NSInteger section = 0; section < CDRAppRowSectionCount; section++) {
        NSMutableArray<CDRAppRowModel *> *members = [NSMutableArray array];
        for (CDRAppRowModel *row in rowModels) {
            if (row.section != section) continue;
            if (needle.length > 0 &&
                [row.appName rangeOfString:needle
                                   options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) {
                continue;
            }
            [members addObject:row];
        }
        if (members.count == 0) continue;
        [items addObject:@(section)];
        [items addObjectsFromArray:members];
    }
    return items;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _rowModels = @[];
    _items = @[];
    return self;
}

- (void)loadView {
    CDRSurfaceView *root = [CDRSurfaceView surfaceWithFill:CDRPalette.sidebarSurface];
    root.translatesAutoresizingMaskIntoConstraints = YES;
    root.frame = NSMakeRect(0, 0, 256, 600);

    self.searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholderString = @"Search apps";
    self.searchField.delegate = self;
    self.searchField.target = self;
    self.searchField.action = @selector(searchChanged:);
    self.searchField.sendsSearchStringImmediately = YES;
    self.searchField.controlSize = NSControlSizeLarge;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.style = NSTableViewStylePlain;
    table.headerView = nil;
    table.backgroundColor = NSColor.clearColor;
    table.intercellSpacing = NSMakeSize(0, 0);
    table.allowsMultipleSelection = NO;
    table.allowsEmptySelection = YES;
    table.floatsGroupRows = NO;
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.dataSource = self;
    table.delegate = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"app"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [table addTableColumn:column];
    table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    table.menu = menu;
    self.tableView = table;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.automaticallyAdjustsContentInsets = NO;

    self.emptyLabel = CDRLabel(@"", [NSFont systemFontOfSize:12], CDRPalette.textSecondary, YES);
    self.emptyLabel.alignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;

    self.progressLabel = CDRLabel(@"", [NSFont systemFontOfSize:11], CDRPalette.textSecondary, NO);
    self.progressBar = [[CDRProgressBarView alloc] initWithFrame:NSZeroRect];
    NSView *progress = [[NSView alloc] initWithFrame:NSZeroRect];
    progress.translatesAutoresizingMaskIntoConstraints = NO;
    [progress addSubview:self.progressLabel];
    [progress addSubview:self.progressBar];
    progress.hidden = YES;
    self.progressContainer = progress;

    for (NSView *view in @[self.searchField, scroll, self.emptyLabel, progress]) [root addSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchField.topAnchor constraintEqualToAnchor:root.topAnchor constant:12],
        [self.searchField.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:10],
        [self.searchField.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-10],

        [scroll.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [self.emptyLabel.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:28],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],

        [progress.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:16],
        [progress.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],
        [progress.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12],
        [self.progressLabel.topAnchor constraintEqualToAnchor:progress.topAnchor constant:8],
        [self.progressLabel.leadingAnchor constraintEqualToAnchor:progress.leadingAnchor],
        [self.progressLabel.trailingAnchor constraintEqualToAnchor:progress.trailingAnchor],
        [self.progressBar.topAnchor constraintEqualToAnchor:self.progressLabel.bottomAnchor constant:5],
        [self.progressBar.leadingAnchor constraintEqualToAnchor:progress.leadingAnchor],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:progress.trailingAnchor],
        [self.progressBar.bottomAnchor constraintEqualToAnchor:progress.bottomAnchor],
    ]];

    self.listBottomToPane = [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor];
    self.listBottomToProgress = [scroll.bottomAnchor constraintEqualToAnchor:progress.topAnchor];
    self.listBottomToPane.active = YES;

    self.view = root;
    [self reloadItems];
}

#pragma mark - Data

- (void)setRowModels:(NSArray<CDRAppRowModel *> *)rowModels {
    _rowModels = [rowModels copy];
    if (self.isViewLoaded) [self reloadItems];
}

- (void)setSelectedBundleID:(NSString *)selectedBundleID {
    _selectedBundleID = [selectedBundleID copy];
    if (self.isViewLoaded) [self applySelection];
}

- (void)searchChanged:(id)sender {
    [self reloadItems];
}

/// Rebuilds the list and restores the selection by bundle ID, so a refresh
/// (every check, every phase change) never moves the user's place.
- (void)reloadItems {
    self.items = [CDRAppListViewController listItemsForRowModels:self.rowModels
                                                          query:self.searchField.stringValue];
    self.reloading = YES;
    [self.tableView reloadData];
    [self applySelection];
    self.reloading = NO;

    BOOL filtering = self.searchField.stringValue.length > 0;
    self.emptyLabel.hidden = (self.items.count > 0);
    self.emptyLabel.stringValue = filtering ? @"No apps match your search." : @"";
}

- (void)applySelection {
    NSInteger index = [self indexOfBundleID:self.selectedBundleID];
    BOOL wasReloading = self.reloading;
    self.reloading = YES;
    if (index == NSNotFound) {
        [self.tableView deselectAll:nil];
    } else {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index]
                    byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:index];
    }
    self.reloading = wasReloading;
}

- (NSInteger)indexOfBundleID:(NSString *)bundleID {
    if (!bundleID) return NSNotFound;
    for (NSUInteger i = 0; i < self.items.count; i++) {
        id item = self.items[i];
        if ([item isKindOfClass:[CDRAppRowModel class]] &&
            [((CDRAppRowModel *)item).bundleID isEqualToString:bundleID]) {
            return (NSInteger)i;
        }
    }
    return NSNotFound;
}

- (nullable CDRAppRowModel *)modelAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return nil;
    id item = self.items[row];
    return [item isKindOfClass:[CDRAppRowModel class]] ? item : nil;
}

- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(NSString *)detail {
    [self view];
    self.progressContainer.hidden = !active;
    // Deactivate before activating, so the two never hold at once.
    if (active) {
        self.listBottomToPane.active = NO;
        self.listBottomToProgress.active = YES;
    } else {
        self.listBottomToProgress.active = NO;
        self.listBottomToPane.active = YES;
    }
    self.progressLabel.stringValue = detail ?: @"";
    self.progressBar.fraction = fraction;
}

#pragma mark - Context menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    CDRAppRowModel *row = [self modelAtRow:self.tableView.clickedRow] ?: [self modelAtRow:self.tableView.selectedRow];
    if (!row) return;

    struct { CDRAppRowActions action; NSString *title; } entries[] = {
        { CDRAppRowActionInstall,       @"Install" },
        { CDRAppRowActionCheckNow,      @"Check Now" },
        { CDRAppRowActionCancelPending, @"Cancel Pending Update" },
        { CDRAppRowActionAcknowledge,   @"Got It" },
        { CDRAppRowActionVendorSite,    @"Developer's Site" },
        { CDRAppRowActionIgnore,        @"Ignore" },
        { CDRAppRowActionUnignore,      @"Stop Ignoring" },
    };
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        if (!(row.actions & entries[i].action)) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entries[i].title
                                                      action:@selector(contextActionClicked:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)entries[i].action;
        item.representedObject = row.bundleID;
        [menu addItem:item];
    }
}

- (void)contextActionClicked:(NSMenuItem *)item {
    NSString *bundleID = item.representedObject;
    if (bundleID && self.onRowAction) self.onRowAction(bundleID, (CDRAppRowActions)item.tag);
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.items.count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    return [self.items[row] isKindOfClass:[NSNumber class]];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return [self modelAtRow:row] != nil;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return [self.items[row] isKindOfClass:[NSNumber class]] ? kHeaderHeight : kRowHeight;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[CDRAppListRowView alloc] initWithFrame:NSZeroRect];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    id item = self.items[row];
    if ([item isKindOfClass:[NSNumber class]]) {
        NSTableCellView *header = [tableView makeViewWithIdentifier:@"header" owner:self];
        if (!header) {
            header = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
            header.identifier = @"header";
            NSTextField *label = CDRLabel(@"", [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
                                          CDRPalette.textSecondary, NO);
            [header addSubview:label];
            header.textField = label;
            [NSLayoutConstraint activateConstraints:@[
                [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
                [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-5],
            ]];
        }
        NSString *title = CDRAppRowSectionTitle((CDRAppRowSection)[item integerValue]);
        header.textField.attributedStringValue = [[NSAttributedString alloc] initWithString:title attributes:@{
            NSKernAttributeName: @0.9,
            NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: CDRPalette.textSecondary,
        }];
        return header;
    }

    CDRAppRowCellView *cell = [tableView makeViewWithIdentifier:@"row" owner:self];
    if (!cell) {
        cell = [[CDRAppRowCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"row";
    }
    [cell configureWithModel:item now:[NSDate date]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (self.reloading) return;
    CDRAppRowModel *row = [self modelAtRow:self.tableView.selectedRow];
    _selectedBundleID = [row.bundleID copy];
    if (self.onSelectionChanged) self.onSelectionChanged(row.bundleID);
}

@end
