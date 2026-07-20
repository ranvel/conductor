//
//  CDRStatusWindowController.m
//  Conductor
//

#import "CDRStatusWindowController.h"
#import "CDRAppRegistration.h"
#import "CDRDevModeSession.h"

@interface CDRStatusWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) NSTableView *tableView;
@property (nonatomic) NSTextView *logView;
@property (nonatomic) NSButton *checkButton;
@property (nonatomic) NSButton *checkAllButton;
@property (nonatomic) NSButton *installButton;
@property (nonatomic) NSMutableDictionary<NSString *, NSString *> *rowStatuses;   // bundleID → Available-column text
@property (nonatomic) NSMutableSet<NSString *> *installEnabledBundleIDs;
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
    _registrations = @[];
    _rowStatuses = [NSMutableDictionary dictionary];
    _installEnabledBundleIDs = [NSMutableSet set];
    [self buildContentView];
    return self;
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
    nameCol.width = 200;
    NSTableColumn *versionCol = [[NSTableColumn alloc] initWithIdentifier:@"version"];
    versionCol.title = @"Installed";
    versionCol.width = 100;
    NSTableColumn *availableCol = [[NSTableColumn alloc] initWithIdentifier:@"available"];
    availableCol.title = @"Available";
    availableCol.width = 100;
    NSTableColumn *bundleCol = [[NSTableColumn alloc] initWithIdentifier:@"bundle"];
    bundleCol.title = @"Bundle ID";
    bundleCol.width = 240;
    [self.tableView addTableColumn:nameCol];
    [self.tableView addTableColumn:versionCol];
    [self.tableView addTableColumn:availableCol];
    [self.tableView addTableColumn:bundleCol];

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
    // a soak; "Check All" is the global scan that never does (deferral.md).
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

- (void)setRegistrations:(NSArray<CDRAppRegistration *> *)registrations {
    _registrations = [registrations copy];
    [self.tableView reloadData];
    [self updateButtonState];
}

- (void)appendLog:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss";
        NSString *stamped = [NSString stringWithFormat:@"[%@] %@\n",
                             [fmt stringFromDate:[NSDate date]], line];
        NSAttributedString *as = [[NSAttributedString alloc] initWithString:stamped attributes:@{
            NSFontAttributeName: self.logView.font ?: [NSFont systemFontOfSize:11],
            NSForegroundColorAttributeName: [NSColor labelColor],
        }];
        [self.logView.textStorage appendAttributedString:as];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
    });
}

- (void)setRowStatus:(NSString *)status installEnabled:(BOOL)enabled forBundleID:(NSString *)bundleID {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (status) {
            self.rowStatuses[bundleID] = status;
        } else {
            [self.rowStatuses removeObjectForKey:bundleID];
        }
        if (enabled) {
            [self.installEnabledBundleIDs addObject:bundleID];
        } else {
            [self.installEnabledBundleIDs removeObject:bundleID];
        }
        [self.tableView reloadData];
        [self updateButtonState];
    });
}

#pragma mark - Actions

- (nullable CDRAppRegistration *)selectedRegistration {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.registrations.count) return nil;
    return self.registrations[row];
}

- (void)checkClicked:(id)sender {
    CDRAppRegistration *reg = [self selectedRegistration];
    if (reg && self.onCheck) self.onCheck(reg);
}

- (void)checkAllClicked:(id)sender {
    if (self.onCheckAll) self.onCheckAll();
}

- (void)installClicked:(id)sender {
    CDRAppRegistration *reg = [self selectedRegistration];
    if (reg && self.onInstall) self.onInstall(reg);
}

- (void)updateButtonState {
    CDRAppRegistration *reg = [self selectedRegistration];
    self.checkButton.enabled = (reg != nil);
    self.checkAllButton.enabled = (self.registrations.count > 0);
    self.installButton.enabled = (reg != nil && [self.installEnabledBundleIDs containsObject:reg.bundleID]);
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.registrations.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    CDRAppRegistration *reg = self.registrations[row];
    NSString *text = @"";
    if ([column.identifier isEqualToString:@"name"]) {
        text = reg.appURL.lastPathComponent.stringByDeletingPathExtension;
    } else if ([column.identifier isEqualToString:@"version"]) {
        text = reg.installedBuildVersion
            ? [NSString stringWithFormat:@"%@ (%@)", reg.installedShortVersion, reg.installedBuildVersion]
            : reg.installedShortVersion;
    } else if ([column.identifier isEqualToString:@"available"]) {
        text = self.rowStatuses[reg.bundleID] ?: @"—";
    } else if ([column.identifier isEqualToString:@"bundle"]) {
        text = reg.bundleID;
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
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateButtonState];
}

@end
