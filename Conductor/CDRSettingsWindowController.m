//
//  CDRSettingsWindowController.m
//  Conductor
//

#import "CDRSettingsWindowController.h"
#import <ServiceManagement/ServiceManagement.h>
#import "CDRAppearanceSettings.h"
#import "CDRCategoryGridView.h"
#import "CDRIgnoreList.h"
#import "CDRPalette.h"
#import "CDRScanScheduler.h"
#import "CDRSharedLog.h"
#import "CDRUpdatePreferences.h"
#import "CDRViews.h"

static const CGFloat kFormWidth = 640;
static const CGFloat kFormInset = 24;
static const CGFloat kCardPadding = 16;

#pragma mark - Interest scheme card

/// One of the three interest-scheme presets: a radio, a name and what it
/// means, selectable as a whole.
@interface CDRSchemeCardView : CDRSurfaceView
@property (nonatomic) BOOL selected;
@property (nonatomic, readonly) NSButton *button;
- (instancetype)initWithTitle:(NSString *)title detail:(NSString *)detail;
@end

@implementation CDRSchemeCardView {
    NSImageView *_radio;
}

- (instancetype)initWithTitle:(NSString *)title detail:(NSString *)detail {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.cornerRadius = 9;
    self.fillColor = CDRPalette.buttonSecondaryFill;

    _radio = CDRSymbolView(@"circle", 14, NSFontWeightRegular, CDRPalette.textSecondary);
    NSTextField *titleLabel = CDRLabel(title, [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],
                                       CDRPalette.textPrimary, NO);
    NSTextField *detailLabel = CDRLabel(detail, [NSFont systemFontOfSize:12.5], CDRPalette.textSecondary, YES);

    // The whole card is the control; the labels and glyph are its face.
    _button = [NSButton buttonWithTitle:@"" target:nil action:NULL];
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    _button.bordered = NO;
    _button.transparent = YES;
    [_button setButtonType:NSButtonTypeMomentaryChange];
    [_button setAccessibilityRole:NSAccessibilityRadioButtonRole];
    [_button setAccessibilityLabel:[NSString stringWithFormat:@"%@. %@", title, detail]];

    for (NSView *view in @[_radio, titleLabel, detailLabel, _button]) [self addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [_radio.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_radio.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [_radio.widthAnchor constraintEqualToConstant:18],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_radio.trailingAnchor constant:6],
        [titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],
        [detailLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [detailLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-12],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:86],
        [_button.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
    self.selected = NO;
    return self;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.borderColor = selected ? CDRPalette.textPrimary : CDRPalette.hairline;
    self.borderWidth = selected ? 1.5 : 1;
    _radio.image = CDRSymbol(selected ? @"circle.inset.filled" : @"circle", 14, NSFontWeightRegular);
    _radio.contentTintColor = selected ? CDRPalette.textPrimary : CDRPalette.textSecondary;
    [_button setAccessibilityValue:@(selected)];
    self.needsDisplay = YES;
}

@end

#pragma mark - Settings

@interface CDRSettingsWindowController () <NSWindowDelegate>
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic) NSScrollView *scrollView;
@property (nonatomic) NSStackView *formStack;
@property (nonatomic) NSMutableDictionary<NSNumber *, NSView *> *sectionTitles;

// Updates
@property (nonatomic) NSSegmentedControl *deferralControl;
@property (nonatomic) NSSwitch *stopAtMajorSwitch;
// What you see
@property (nonatomic) NSArray<CDRSchemeCardView *> *schemeCards;
@property (nonatomic) CDRCategoryGridView *shownGrid;
// Install manually when…
@property (nonatomic) CDRCategoryGridView *holdGrid;
// Network
@property (nonatomic) NSSwitch *requireApprovalSwitch;
@property (nonatomic) NSSwitch *policyExemptsSwitch;
@property (nonatomic) NSTextField *policyExemptsTitle;
@property (nonatomic) NSTextField *policyExemptsCaption;
// Conductor (M3)
@property (nonatomic) NSButton *loginItemCheckbox;
@property (nonatomic) NSTextField *loginItemStatusLabel;
@property (nonatomic) NSButton *openLoginItemsButton;
@property (nonatomic) NSButton *menuBarCheckbox;
@property (nonatomic) NSButton *dockIconCheckbox;
@property (nonatomic) NSPopUpButton *cadencePopup;
@property (nonatomic) NSStackView *ignoreStack;
@end

@implementation CDRSettingsWindowController

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kFormWidth, 720)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Conductor Settings";
    // The form has one width; only its height is the user's to change.
    window.contentMinSize = NSMakeSize(kFormWidth, 360);
    window.contentMaxSize = NSMakeSize(kFormWidth, 10000);
    window.releasedWhenClosed = NO;
    [window center];

    self = [super initWithWindow:window];
    if (!self) return nil;
    _defaults = defaults;
    _rowModels = @[];
    _sectionTitles = [NSMutableDictionary dictionary];
    window.delegate = self;
    [self buildContentView];
    [self refreshFromDefaults];
    return self;
}

#pragma mark - Layout helpers

- (NSTextField *)captionLabel:(NSString *)text {
    return CDRLabel(text, [NSFont systemFontOfSize:12], CDRPalette.textSecondary, YES);
}

- (NSTextField *)rowTitle:(NSString *)text {
    return CDRLabel(text, [NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium], CDRPalette.textPrimary, NO);
}

- (NSView *)spacer {
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spacer;
}

- (NSStackView *)vertical:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    return stack;
}

- (NSStackView *)horizontal:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    return stack;
}

/// A title + caption on the left, a control on the right.
- (NSView *)rowWithTitle:(NSTextField *)title caption:(nullable NSTextField *)caption control:(NSView *)control {
    NSMutableArray<NSView *> *texts = [NSMutableArray arrayWithObject:title];
    if (caption) [texts addObject:caption];
    NSStackView *text = [self vertical:texts spacing:3];
    if (caption) [caption.widthAnchor constraintLessThanOrEqualToConstant:340].active = YES;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return [self horizontal:@[text, [self spacer], control] spacing:12];
}

/// A rounded card whose rows are separated by hairlines. `indents` gives a
/// leading inset per row (the nested network toggle).
- (NSView *)cardWithRows:(NSArray<NSView *> *)rows indents:(nullable NSArray<NSNumber *> *)indents {
    CDRSurfaceView *card = [CDRSurfaceView cardWithFill:CDRPalette.cardSurface border:CDRPalette.hairline radius:10];
    NSLayoutYAxisAnchor *top = card.topAnchor;
    for (NSUInteger i = 0; i < rows.count; i++) {
        NSView *row = rows[i];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:row];
        CGFloat indent = (i < indents.count) ? indents[i].doubleValue : 0;
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:top constant:13],
            [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:kCardPadding + indent],
            [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-kCardPadding],
        ]];
        if (i + 1 < rows.count) {
            CDRHairlineView *line = [[CDRHairlineView alloc] initWithFrame:NSZeroRect];
            [card addSubview:line];
            [NSLayoutConstraint activateConstraints:@[
                [line.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:13],
                [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
                [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            ]];
            top = line.bottomAnchor;
        } else {
            [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-13].active = YES;
        }
    }
    return card;
}

- (void)addSection:(CDRSettingsSection)section title:(NSString *)title card:(NSView *)card {
    NSTextField *label = CDRLabel(title, [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium],
                                  CDRPalette.textSecondary, NO);
    self.sectionTitles[@(section)] = label;
    NSView *last = self.formStack.arrangedSubviews.lastObject;
    [self.formStack addArrangedSubview:label];
    [self.formStack addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:self.formStack.widthAnchor].active = YES;
    if (last) [self.formStack setCustomSpacing:26 afterView:last];
    [self.formStack setCustomSpacing:8 afterView:label];
}

#pragma mark - Build

- (void)buildContentView {
    CDRSurfaceView *root = [CDRSurfaceView surfaceWithFill:CDRPalette.titleBarSurface];
    root.translatesAutoresizingMaskIntoConstraints = YES;
    root.frame = NSMakeRect(0, 0, kFormWidth, 720);
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    self.formStack = stack;

    CDRFlippedView *document = [[CDRFlippedView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasVerticalScroller = YES;
    scroll.documentView = document;
    self.scrollView = scroll;
    [root addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:kFormInset],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-kFormInset],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-28],
    ]];
    self.window.contentView = root;

    [self buildUpdatesSection];
    [self buildWhatYouSeeSection];
    [self buildInstallManuallySection];
    [self buildNetworkSection];
    [self buildConductorSection];
    [self buildIgnoredAppsSection];
}

- (void)buildUpdatesSection {
    // Deferral ("soak" never appears in UI copy). Segments follow
    // CDRSoakDurationChoices(), not the enum's raw values.
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSNumber *choice in CDRSoakDurationChoices()) {
        [labels addObject:CDRSoakDurationDisplayName((CDRSoakDuration)choice.integerValue)];
    }
    self.deferralControl = [NSSegmentedControl segmentedControlWithLabels:labels
                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                  target:self
                                                                  action:@selector(deferralChanged:)];
    [self.deferralControl setAccessibilityLabel:@"Defer new updates"];
    NSView *deferRow = [self rowWithTitle:[self rowTitle:@"Defer new updates"]
                                  caption:[self captionLabel:@"New builds stay hidden this long. Checking one app by hand always shows its newest build."]
                                  control:self.deferralControl];

    self.stopAtMajorSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.stopAtMajorSwitch.target = self;
    self.stopAtMajorSwitch.action = @selector(stopAtMajorChanged:);
    [self.stopAtMajorSwitch setAccessibilityLabel:@"Stop at major versions"];
    NSView *majorRow = [self rowWithTitle:[self rowTitle:@"Stop at major versions"]
                                  caption:[self captionLabel:@"Hold 2.0, 3.0 and so on until you choose to install them."]
                                  control:self.stopAtMajorSwitch];

    [self addSection:CDRSettingsSectionUpdates title:@"Updates" card:[self cardWithRows:@[deferRow, majorRow] indents:nil]];
}

- (void)buildWhatYouSeeSection {
    NSArray<NSArray<NSString *> *> *schemes = @[
        @[@"Normal user", @"What changes how you use the app. Security details collapse."],
        @[@"Everything", @"Every note in every category."],
        @[@"Developer", @"Everything, plus manifest and entitlement details."],
    ];
    NSMutableArray<CDRSchemeCardView *> *cards = [NSMutableArray array];
    for (NSUInteger i = 0; i < schemes.count; i++) {
        CDRSchemeCardView *card = [[CDRSchemeCardView alloc] initWithTitle:schemes[i][0] detail:schemes[i][1]];
        card.button.target = self;
        card.button.action = @selector(schemeChosen:);
        card.button.tag = (NSInteger)i;   // CDRInterestScheme Normal / Everything / Developer
        [cards addObject:card];
    }
    self.schemeCards = cards;
    NSStackView *cardRow = [self horizontal:cards spacing:8];
    cardRow.distribution = NSStackViewDistributionFillEqually;
    cardRow.alignment = NSLayoutAttributeTop;
    for (CDRSchemeCardView *card in cards) {
        [card.heightAnchor constraintEqualToAnchor:cards.firstObject.heightAnchor].active = YES;
    }
    NSStackView *schemeRow = [self vertical:@[[self rowTitle:@"Interest scheme"], cardRow] spacing:10];
    [cardRow.widthAnchor constraintEqualToAnchor:schemeRow.widthAnchor].active = YES;

    self.shownGrid = [[CDRCategoryGridView alloc] initWithColumns:4 showsRetracted:YES compact:NO];
    __weak typeof(self) weakSelf = self;
    self.shownGrid.onChange = ^(CDRReleaseNoteTypeSet types) {
        [weakSelf updatePreferences:^(CDRMutableUpdatePreferences *prefs) {
            prefs.shownTypes = types;   // by hand: no preset stays selected
        }];
    };
    NSTextField *hint = CDRLabel(@"Unchecked ones collapse to a one-line count", [NSFont systemFontOfSize:12],
                                 CDRPalette.textSecondary, NO);
    NSStackView *shownHeader = [self horizontal:@[[self rowTitle:@"Shown categories"], [self spacer], hint] spacing:8];
    NSStackView *shownRow = [self vertical:@[shownHeader, self.shownGrid] spacing:12];
    [shownHeader.widthAnchor constraintEqualToAnchor:shownRow.widthAnchor].active = YES;

    [self addSection:CDRSettingsSectionWhatYouSee title:@"What you see"
                card:[self cardWithRows:@[schemeRow, shownRow] indents:nil]];
}

- (void)buildInstallManuallySection {
    self.holdGrid = [[CDRCategoryGridView alloc] initWithColumns:4 showsRetracted:YES compact:NO];
    __weak typeof(self) weakSelf = self;
    self.holdGrid.onChange = ^(CDRReleaseNoteTypeSet types) {
        [weakSelf updatePreferences:^(CDRMutableUpdatePreferences *prefs) {
            prefs.holdTypes = types;
        }];
    };
    [self addSection:CDRSettingsSectionInstallManually title:@"Install manually when an update includes…"
                card:[self cardWithRows:@[self.holdGrid] indents:nil]];
}

- (void)buildNetworkSection {
    self.requireApprovalSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.requireApprovalSwitch.target = self;
    self.requireApprovalSwitch.action = @selector(networkToggled:);
    [self.requireApprovalSwitch setAccessibilityLabel:@"Require approval when an app gains internet access"];
    NSView *requireRow = [self rowWithTitle:[self rowTitle:@"Require approval when an app gains internet access"]
                                    caption:[self captionLabel:@"Conductor compares entitlements with the build you have. For an app with no network access, it downloads and verifies a new build first."]
                                    control:self.requireApprovalSwitch];

    self.policyExemptsSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.policyExemptsSwitch.target = self;
    self.policyExemptsSwitch.action = @selector(networkToggled:);
    [self.policyExemptsSwitch setAccessibilityLabel:@"Unless it ships an Internet Access Policy"];
    self.policyExemptsTitle = [self rowTitle:@"…unless it ships an Internet Access Policy"];
    self.policyExemptsCaption = [self captionLabel:@"Apps that say where they connect, and why, update without asking."];
    NSView *exemptRow = [self rowWithTitle:self.policyExemptsTitle
                                   caption:self.policyExemptsCaption
                                   control:self.policyExemptsSwitch];

    [self addSection:CDRSettingsSectionNetwork title:@"Network"
                card:[self cardWithRows:@[requireRow, exemptRow] indents:@[@0, @24]]];
}

- (void)buildConductorSection {
    // Login item.
    self.loginItemCheckbox = [NSButton checkboxWithTitle:@"Start Conductor at login"
                                                  target:self action:@selector(loginItemToggled:)];
    self.loginItemStatusLabel = [self captionLabel:@""];
    self.openLoginItemsButton = [NSButton buttonWithTitle:@"Open Login Items Settings…"
                                                   target:self action:@selector(openLoginItems:)];
    self.openLoginItemsButton.hidden = YES;
    self.loginItemStatusLabel.hidden = YES;
    NSStackView *loginRow = [self vertical:@[self.loginItemCheckbox, self.loginItemStatusLabel,
                                             self.openLoginItemsButton] spacing:6];

    // Visibility. Disabling one locks the other on: never invisible.
    self.menuBarCheckbox = [NSButton checkboxWithTitle:@"Show Conductor in the menu bar"
                                                target:self action:@selector(appearanceToggled:)];
    self.dockIconCheckbox = [NSButton checkboxWithTitle:@"Show Conductor in the Dock"
                                                 target:self action:@selector(appearanceToggled:)];
    NSStackView *visibilityRow = [self vertical:@[self.menuBarCheckbox, self.dockIconCheckbox,
        [self captionLabel:@"At least one stays on, so Conductor is always reachable."]] spacing:6];

    // Scan cadence.
    self.cadencePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.cadencePopup addItemsWithTitles:@[@"Every 6 hours", @"Daily", @"Weekly", @"Manually"]];
    self.cadencePopup.target = self;
    self.cadencePopup.action = @selector(cadenceChanged:);
    [self.cadencePopup setAccessibilityLabel:@"Check for updates"];
    NSView *cadenceRow = [self rowWithTitle:[self rowTitle:@"Check for updates"] caption:nil control:self.cadencePopup];

    [self addSection:CDRSettingsSectionConductor title:@"Conductor"
                card:[self cardWithRows:@[loginRow, visibilityRow, cadenceRow] indents:nil]];
}

- (void)buildIgnoredAppsSection {
    self.ignoreStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.ignoreStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.ignoreStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.ignoreStack.alignment = NSLayoutAttributeLeading;
    self.ignoreStack.spacing = 5;
    NSStackView *row = [self vertical:@[
        [self captionLabel:@"Ignored apps are skipped by scheduled checks. Checking one by hand still works."],
        self.ignoreStack] spacing:10];
    [self addSection:CDRSettingsSectionIgnoredApps title:@"Ignored apps" card:[self cardWithRows:@[row] indents:nil]];
    [self rebuildIgnoreList];
}

#pragma mark - State

/// Reads the stored preferences, applies one change, writes them back, and
/// redraws every control from what is now stored.
- (void)updatePreferences:(void (^)(CDRMutableUpdatePreferences *prefs))change {
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences preferencesFromDefaults:self.defaults] mutableCopy];
    change(prefs);
    [prefs writeToDefaults:self.defaults];
    [self refreshFromDefaults];
    if (self.onPreferencesChanged) self.onPreferencesChanged();
}

- (void)refreshFromDefaults {
    [self refreshLoginItemStatus];

    BOOL menuBar = CDRShowMenuBarItemSetting(self.defaults);
    BOOL dock = CDRShowDockIconSetting(self.defaults);
    self.menuBarCheckbox.state = menuBar ? NSControlStateValueOn : NSControlStateValueOff;
    self.dockIconCheckbox.state = dock ? NSControlStateValueOn : NSControlStateValueOff;
    self.menuBarCheckbox.enabled = dock;
    self.dockIconCheckbox.enabled = menuBar;

    CDRUpdatePreferences *prefs = [CDRUpdatePreferences preferencesFromDefaults:self.defaults];

    NSUInteger deferIndex = [CDRSoakDurationChoices() indexOfObject:@(prefs.soakDuration)];
    self.deferralControl.selectedSegment = (deferIndex == NSNotFound) ? 0 : (NSInteger)deferIndex;
    self.stopAtMajorSwitch.state = prefs.stopAtMajorVersions ? NSControlStateValueOn : NSControlStateValueOff;

    // A hand-edited grid (Custom) leaves all three presets deselected.
    for (NSUInteger i = 0; i < self.schemeCards.count; i++) {
        self.schemeCards[i].selected = ((NSInteger)i == (NSInteger)prefs.interestScheme);
    }
    self.shownGrid.selectedTypes = prefs.shownTypes;
    self.holdGrid.selectedTypes = prefs.holdTypes;

    self.requireApprovalSwitch.state = prefs.requireNetworkApproval ? NSControlStateValueOn : NSControlStateValueOff;
    self.policyExemptsSwitch.state = prefs.policyExemptsApproval ? NSControlStateValueOn : NSControlStateValueOff;
    // The exemption only means something while approval is required.
    self.policyExemptsSwitch.enabled = prefs.requireNetworkApproval;
    NSColor *exemptInk = prefs.requireNetworkApproval ? CDRPalette.textPrimary : CDRPalette.textSecondary;
    self.policyExemptsTitle.textColor = exemptInk;

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
            self.loginItemStatusLabel.hidden = NO;
            self.openLoginItemsButton.hidden = NO;
            break;
        default:
            self.loginItemStatusLabel.stringValue = @"";
            self.loginItemStatusLabel.hidden = YES;
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

- (void)showSection:(CDRSettingsSection)section {
    NSView *title = self.sectionTitles[@(section)];
    if (!title) return;
    [self.window.contentView layoutSubtreeIfNeeded];
    NSView *document = self.scrollView.documentView;
    NSRect frame = [title convertRect:title.bounds toView:document];
    CGFloat maxY = MAX(0, NSHeight(document.frame) - NSHeight(self.scrollView.contentView.bounds));
    NSPoint origin = NSMakePoint(0, MIN(MAX(NSMinY(frame) - 14, 0), maxY));
    [self.scrollView.contentView scrollToPoint:origin];
    [self.scrollView reflectScrolledClipView:self.scrollView.contentView];
}

#pragma mark - Actions

- (void)deferralChanged:(NSSegmentedControl *)sender {
    NSArray<NSNumber *> *choices = CDRSoakDurationChoices();
    NSInteger index = sender.selectedSegment;
    if (index < 0 || index >= (NSInteger)choices.count) return;
    CDRSoakDuration soak = (CDRSoakDuration)choices[index].integerValue;
    [self updatePreferences:^(CDRMutableUpdatePreferences *prefs) {
        prefs.soakDuration = soak;
    }];
}

- (void)stopAtMajorChanged:(NSSwitch *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [self updatePreferences:^(CDRMutableUpdatePreferences *prefs) {
        prefs.stopAtMajorVersions = on;
    }];
}

- (void)schemeChosen:(NSButton *)sender {
    CDRInterestScheme scheme = (CDRInterestScheme)sender.tag;
    [self updatePreferences:^(CDRMutableUpdatePreferences *prefs) {
        prefs.interestScheme = scheme;   // also seeds the shown categories
    }];
}

- (void)networkToggled:(id)sender {
    BOOL require = (self.requireApprovalSwitch.state == NSControlStateValueOn);
    BOOL exempts = (self.policyExemptsSwitch.state == NSControlStateValueOn);
    [self updatePreferences:^(CDRMutableUpdatePreferences *prefs) {
        prefs.requireNetworkApproval = require;
        prefs.policyExemptsApproval = exempts;
    }];
}

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
    // in the background; a `defaults write` may have changed a policy.
    [self refreshFromDefaults];
}

@end
