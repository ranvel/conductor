//
//  CDRSettingsWindowController.m
//  Conductor
//

#import "CDRSettingsWindowController.h"
#import <ServiceManagement/ServiceManagement.h>
#import "CDRAppearanceSettings.h"
#import "CDRIgnoreList.h"
#import "CDRScanScheduler.h"
#import "CDRSharedLog.h"
#import "CDRUpdatePolicy.h"

@interface CDRSettingsWindowController () <NSWindowDelegate>
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic) NSButton *loginItemCheckbox;
@property (nonatomic) NSTextField *loginItemStatusLabel;
@property (nonatomic) NSButton *openLoginItemsButton;
@property (nonatomic) NSButton *menuBarCheckbox;
@property (nonatomic) NSButton *dockIconCheckbox;
@property (nonatomic) NSPopUpButton *deferralPopup;
@property (nonatomic) NSPopUpButton *cadencePopup;
@property (nonatomic) NSStackView *ignoreStack;
@end

@implementation CDRSettingsWindowController

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 440, 480)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Conductor Settings";
    [window center];

    self = [super initWithWindow:window];
    if (!self) return nil;
    _defaults = defaults;
    _rowModels = @[];
    window.delegate = self;
    [self buildContentView];
    [self refreshFromDefaults];
    return self;
}

#pragma mark - Layout

- (NSTextField *)captionLabel:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (void)buildContentView {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *content = self.window.contentView;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    ]];

    // Login item.
    self.loginItemCheckbox = [NSButton checkboxWithTitle:@"Start Conductor at login"
                                                  target:self action:@selector(loginItemToggled:)];
    [stack addArrangedSubview:self.loginItemCheckbox];
    self.loginItemStatusLabel = [self captionLabel:@""];
    [stack addArrangedSubview:self.loginItemStatusLabel];
    self.openLoginItemsButton = [NSButton buttonWithTitle:@"Open Login Items Settings…"
                                                   target:self action:@selector(openLoginItems:)];
    self.openLoginItemsButton.hidden = YES;
    [stack addArrangedSubview:self.openLoginItemsButton];

    [stack addArrangedSubview:[self separator]];

    // Visibility. Disabling one locks the other on: never invisible.
    self.menuBarCheckbox = [NSButton checkboxWithTitle:@"Show Conductor in the menu bar"
                                                target:self action:@selector(appearanceToggled:)];
    self.dockIconCheckbox = [NSButton checkboxWithTitle:@"Show Conductor in the Dock"
                                                 target:self action:@selector(appearanceToggled:)];
    [stack addArrangedSubview:self.menuBarCheckbox];
    [stack addArrangedSubview:self.dockIconCheckbox];
    [stack addArrangedSubview:[self captionLabel:
        @"At least one stays on, so Conductor is always reachable."]];

    [stack addArrangedSubview:[self separator]];

    // Deferral duration ("soak" never appears in UI copy).
    NSStackView *deferralRow = [self labeledRow:@"Delay new updates:"];
    self.deferralPopup = [[NSPopUpButton alloc] init];
    [self.deferralPopup addItemsWithTitles:@[@"Off", @"1 day", @"1 week"]];
    self.deferralPopup.target = self;
    self.deferralPopup.action = @selector(deferralChanged:);
    [deferralRow addArrangedSubview:self.deferralPopup];
    [stack addArrangedSubview:deferralRow];
    [stack addArrangedSubview:[self captionLabel:
        @"Wait before offering a new version, in case the developer withdraws a release."]];

    // Scan cadence.
    NSStackView *cadenceRow = [self labeledRow:@"Check for updates:"];
    self.cadencePopup = [[NSPopUpButton alloc] init];
    [self.cadencePopup addItemsWithTitles:@[@"Every 6 hours", @"Daily", @"Weekly", @"Manually"]];
    self.cadencePopup.target = self;
    self.cadencePopup.action = @selector(cadenceChanged:);
    [cadenceRow addArrangedSubview:self.cadencePopup];
    [stack addArrangedSubview:cadenceRow];

    [stack addArrangedSubview:[self separator]];

    // Ignore list.
    NSTextField *ignoreTitle = [NSTextField labelWithString:@"Ignored apps"];
    ignoreTitle.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    [stack addArrangedSubview:ignoreTitle];
    [stack addArrangedSubview:[self captionLabel:
        @"Ignored apps are skipped by scheduled checks. Check Now still works on them."]];
    self.ignoreStack = [[NSStackView alloc] init];
    self.ignoreStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.ignoreStack.alignment = NSLayoutAttributeLeading;
    self.ignoreStack.spacing = 4;
    [stack addArrangedSubview:self.ignoreStack];
    [self rebuildIgnoreList];
}

- (NSBox *)separator {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box.widthAnchor constraintEqualToConstant:400].active = YES;
    return box;
}

- (NSStackView *)labeledRow:(NSString *)label {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    [row addArrangedSubview:[NSTextField labelWithString:label]];
    return row;
}

#pragma mark - State

- (void)refreshFromDefaults {
    [self refreshLoginItemStatus];

    BOOL menuBar = CDRShowMenuBarItemSetting(self.defaults);
    BOOL dock = CDRShowDockIconSetting(self.defaults);
    self.menuBarCheckbox.state = menuBar ? NSControlStateValueOn : NSControlStateValueOff;
    self.dockIconCheckbox.state = dock ? NSControlStateValueOn : NSControlStateValueOff;
    self.menuBarCheckbox.enabled = dock;
    self.dockIconCheckbox.enabled = menuBar;

    CDRSoakDuration soak = CDRSoakDurationFromDefaultsToken(
        [self.defaults stringForKey:CDRSoakDurationDefaultsKey]);
    [self.deferralPopup selectItemAtIndex:soak]; // enum order matches items

    CDRScanCadence cadence = CDRScanCadenceFromDefaultsToken(
        [self.defaults stringForKey:CDRScanCadenceDefaultsKey]);
    NSInteger cadenceIndex;
    switch (cadence) {
        case CDRScanCadenceSixHours: cadenceIndex = 0; break;
        case CDRScanCadenceDaily:    cadenceIndex = 1; break;
        case CDRScanCadenceWeekly:   cadenceIndex = 2; break;
        case CDRScanCadenceManual:   cadenceIndex = 3; break;
    }
    [self.cadencePopup selectItemAtIndex:cadenceIndex];
}

- (void)refreshLoginItemStatus {
    SMAppService *service = [SMAppService mainAppService];
    self.loginItemCheckbox.state =
        (service.status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    switch (service.status) {
        case SMAppServiceStatusRequiresApproval:
            self.loginItemStatusLabel.stringValue =
                @"Waiting for approval in System Settings › Login Items.";
            self.openLoginItemsButton.hidden = NO;
            break;
        default:
            self.loginItemStatusLabel.stringValue = @"";
            self.openLoginItemsButton.hidden = YES;
            break;
    }
}

- (void)setRowModels:(NSArray<CDRAppRowModel *> *)rowModels {
    _rowModels = [rowModels copy];
    [self rebuildIgnoreList];
}

- (void)rebuildIgnoreList {
    for (NSView *view in [self.ignoreStack.arrangedSubviews copy]) {
        [self.ignoreStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (self.rowModels.count == 0) {
        [self.ignoreStack addArrangedSubview:[self captionLabel:@"No managed apps found."]];
        return;
    }
    NSSet<NSString *> *ignored = CDRIgnoredBundleIDs(self.defaults);
    for (CDRAppRowModel *row in self.rowModels) {
        NSButton *checkbox = [NSButton checkboxWithTitle:row.appName
                                                  target:self action:@selector(ignoreToggled:)];
        checkbox.state = [ignored containsObject:row.bundleID]
            ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.identifier = row.bundleID;
        [self.ignoreStack addArrangedSubview:checkbox];
    }
}

#pragma mark - Actions

- (void)loginItemToggled:(NSButton *)sender {
    SMAppService *service = [SMAppService mainAppService];
    NSError *error = nil;
    BOOL ok;
    if (sender.state == NSControlStateValueOn) {
        ok = [service registerAndReturnError:&error];
    } else {
        ok = [service unregisterAndReturnError:&error];
    }
    if (!ok && error) {
        [CDRSharedLog log:[NSString stringWithFormat:@"Login item change failed: %@",
                           error.localizedDescription]];
    }
    [self refreshLoginItemStatus];
}

- (void)openLoginItems:(id)sender {
    [SMAppService openSystemSettingsLoginItems];
}

- (void)appearanceToggled:(NSButton *)sender {
    [self.defaults setBool:(self.menuBarCheckbox.state == NSControlStateValueOn)
                    forKey:CDRShowMenuBarItemDefaultsKey];
    [self.defaults setBool:(self.dockIconCheckbox.state == NSControlStateValueOn)
                    forKey:CDRShowDockIconDefaultsKey];
    [self refreshFromDefaults]; // re-applies the never-both-off lock
    if (self.onAppearanceChanged) self.onAppearanceChanged();
}

- (void)deferralChanged:(id)sender {
    CDRSoakDuration soak = (CDRSoakDuration)self.deferralPopup.indexOfSelectedItem;
    [self.defaults setObject:CDRSoakDurationDefaultsToken(soak)
                      forKey:CDRSoakDurationDefaultsKey];
}

- (void)cadenceChanged:(id)sender {
    CDRScanCadence cadence;
    switch (self.cadencePopup.indexOfSelectedItem) {
        case 0: cadence = CDRScanCadenceSixHours; break;
        case 2: cadence = CDRScanCadenceWeekly; break;
        case 3: cadence = CDRScanCadenceManual; break;
        default: cadence = CDRScanCadenceDaily; break;
    }
    [self.defaults setObject:CDRScanCadenceDefaultsToken(cadence)
                      forKey:CDRScanCadenceDefaultsKey];
    if (self.onCadenceChanged) self.onCadenceChanged();
    if (cadence != CDRScanCadenceManual && self.onRequestFullNotificationAuthorization) {
        // The user just opted into background checks — the earned moment for
        // the notification permission prompt.
        self.onRequestFullNotificationAuthorization();
    }
}

- (void)ignoreToggled:(NSButton *)sender {
    NSString *bundleID = sender.identifier;
    if (!bundleID.length || !self.onRowAction) return;
    self.onRowAction(bundleID, (sender.state == NSControlStateValueOn)
        ? CDRAppRowActionIgnore : CDRAppRowActionUnignore);
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    // Login-item approval may have changed in System Settings while we were
    // in the background.
    [self refreshLoginItemStatus];
}

@end
