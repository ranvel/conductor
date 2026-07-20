//
//  CDRStatusWindowController.m
//  Conductor
//

#import "CDRStatusWindowController.h"
#import "CDRDevModeSession.h"
#import "CDRSharedLog.h"

@interface CDRStatusWindowController () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) NSTableView *tableView;
@property (nonatomic) NSTextView *logView;
@property (nonatomic) NSButton *checkButton;
@property (nonatomic) NSButton *checkAllButton;
@property (nonatomic) NSButton *installButton;
@property (nonatomic) id logObserver;
@end

@implementation CDRStatusWindowController

- (instancetype)initWithSession:(CDRDevModeSession *)session {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 720, 480)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Conductor";
    [window center];

    self = [super initWithWindow:window];
    if (!self) return nil;

    _session = session;
    _rowModels = @[];
    [self buildContentView];

    for (NSString *line in [CDRSharedLog bufferedLines]) {
        [self appendLine:line];
    }
    __weak typeof(self) weakSelf = self;
    _logObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:CDRSharedLogDidAppendNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [weakSelf appendLine:note.userInfo[CDRSharedLogLineKey]];
    }];
    return self;
}

- (void)dealloc {
    if (_logObserver) [[NSNotificationCenter defaultCenter] removeObserver:_logObserver];
}

- (void)buildContentView {
    NSView *content = self.window.contentView;
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    if (self.session.devModeEnabled) {
        NSTextField *banner = [NSTextField wrappingLabelWithString:
            [NSString stringWithFormat:@"DEV MODE — %@ — insecure connections permitted",
             self.session.devModeBundleID]];
        banner.font = [NSFont boldSystemFontOfSize:14];
        banner.textColor = [NSColor whiteColor];
        banner.backgroundColor = [NSColor systemRedColor];
        banner.drawsBackground = YES;
        banner.alignment = NSTextAlignmentCenter;
        banner.translatesAutoresizingMaskIntoConstraints = NO;
        [stack addArrangedSubview:banner];
        [banner.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
    }

    self.tableView = [[NSTableView alloc] init];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.allowsMultipleSelection = NO;

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"App";
    nameCol.width = 180;
    NSTableColumn *versionCol = [[NSTableColumn alloc] initWithIdentifier:@"version"];
    versionCol.title = @"Installed";
    versionCol.width = 90;
    NSTableColumn *statusCol = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    statusCol.title = @"Status";
    statusCol.width = 230;
    NSTableColumn *bundleCol = [[NSTableColumn alloc] initWithIdentifier:@"bundle"];
    bundleCol.title = @"Bundle ID";
    bundleCol.width = 200;
    [self.tableView addTableColumn:nameCol];
    [self.tableView addTableColumn:versionCol];
    [self.tableView addTableColumn:statusCol];
    [self.tableView addTableColumn:bundleCol];

    NSMenu *rowMenu = [[NSMenu alloc] init];
    rowMenu.delegate = self;
    self.tableView.menu = rowMenu;

    NSScrollView *tableScroll = [[NSScrollView alloc] init];
    tableScroll.documentView = self.tableView;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:tableScroll];
    [tableScroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
    [tableScroll.heightAnchor constraintGreaterThanOrEqualToConstant:160].active = YES;

    NSStackView *buttons = [[NSStackView alloc] init];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    // "Check Now" on a specific app is the deliberate act that breaks through
    // a deferral; "Check All" is the global sweep that never does (deferral.md).
    self.checkButton = [NSButton buttonWithTitle:@"Check Now" target:self action:@selector(checkClicked:)];
    self.checkAllButton = [NSButton buttonWithTitle:@"Check All" target:self action:@selector(checkAllClicked:)];
    self.installButton = [NSButton buttonWithTitle:@"Install" target:self action:@selector(installClicked:)];
    self.installButton.enabled = NO;
    [buttons addArrangedSubview:self.checkButton];
    [buttons addArrangedSubview:self.checkAllButton];
    [buttons addArrangedSubview:self.installButton];
    [stack addArrangedSubview:buttons];

    self.logView = [[NSTextView alloc] init];
    self.logView.editable = NO;
    self.logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.logView.autoresizingMask = NSViewWidthSizable;
    NSScrollView *logScroll = [[NSScrollView alloc] init];
    logScroll.documentView = self.logView;
    logScroll.hasVerticalScroller = YES;
    logScroll.borderType = NSBezelBorder;
    logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:logScroll];
    [logScroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
    [logScroll.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;

    [self updateButtonState];
}

#pragma mark - Public

- (void)setRowModels:(NSArray<CDRAppRowModel *> *)rowModels {
    _rowModels = [rowModels copy];
    [self.tableView reloadData];
    [self updateButtonState];
}

#pragma mark - Log rendering

- (void)appendLine:(NSString *)line {
    if (!line) return;
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                             attributes:@{
        NSFontAttributeName: self.logView.font ?: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor labelColor],
    }];
    [self.logView.textStorage appendAttributedString:as];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
}

#pragma mark - Actions

- (nullable CDRAppRowModel *)selectedRow {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rowModels.count) return nil;
    return self.rowModels[row];
}

- (nullable CDRAppRowModel *)clickedOrSelectedRow {
    NSInteger row = self.tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)self.rowModels.count) return self.rowModels[row];
    return [self selectedRow];
}

- (void)sendAction:(CDRAppRowActions)action forRow:(nullable CDRAppRowModel *)row {
    if (row && (row.actions & action) && self.onRowAction) {
        self.onRowAction(row.bundleID, action);
    }
}

- (void)checkClicked:(id)sender {
    [self sendAction:CDRAppRowActionCheckNow forRow:[self selectedRow]];
}

- (void)checkAllClicked:(id)sender {
    if (self.onCheckAll) self.onCheckAll();
}

- (void)installClicked:(id)sender {
    [self sendAction:CDRAppRowActionInstall forRow:[self selectedRow]];
}

- (void)contextActionClicked:(NSMenuItem *)item {
    [self sendAction:(CDRAppRowActions)item.tag forRow:[self clickedOrSelectedRow]];
}

- (void)updateButtonState {
    CDRAppRowModel *row = [self selectedRow];
    self.checkButton.enabled = (row != nil && (row.actions & CDRAppRowActionCheckNow));
    self.checkAllButton.enabled = (self.rowModels.count > 0);
    self.installButton.enabled = (row != nil && (row.actions & CDRAppRowActionInstall));
}

#pragma mark - Row context menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    CDRAppRowModel *row = [self clickedOrSelectedRow];
    if (!row) return;

    struct { CDRAppRowActions action; NSString *title; } entries[] = {
        { CDRAppRowActionInstall,       @"Install" },
        { CDRAppRowActionCheckNow,      @"Check Now" },
        { CDRAppRowActionCancelPending, @"Cancel Pending Update" },
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
        [menu addItem:item];
    }
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.rowModels.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    CDRAppRowModel *model = self.rowModels[row];
    NSString *text = @"";
    if ([column.identifier isEqualToString:@"name"]) {
        text = model.appName;
    } else if ([column.identifier isEqualToString:@"version"]) {
        text = model.installedVersionDisplay;
    } else if ([column.identifier isEqualToString:@"status"]) {
        text = model.stateLine;
    } else if ([column.identifier isEqualToString:@"bundle"]) {
        text = model.bundleID;
    }

    NSTableCellView *cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = column.identifier;
        NSTextField *field = [NSTextField labelWithString:@""];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:field];
        cell.textField = field;
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    cell.textField.stringValue = text;
    cell.textField.textColor = (model.state == CDRAppRowStateIgnored)
        ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateButtonState];
}

@end
