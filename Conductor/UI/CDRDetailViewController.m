//
//  CDRDetailViewController.m
//  Conductor
//

#import "CDRDetailViewController.h"
#import "CDRInternetAccessPolicy.h"
#import "CDRPalette.h"
#import "CDRViews.h"
#import "CDRWindowCopy.h"

static const CGFloat kSideInset = 40;
static const CGFloat kBadgeColumnWidth = 128;
static const CGFloat kMaxContentWidth = 980;

@interface CDRDetailViewController ()
@property (nonatomic) NSScrollView *scrollView;
@property (nonatomic) NSStackView *contentStack;
@property (nonatomic) NSView *centeredContainer;
/// "bundleID|version" of skipped-version rows the user expanded.
@property (nonatomic) NSMutableSet<NSString *> *expandedKeys;
/// "bundleID|version|type" of collapsed categories the user revealed.
@property (nonatomic) NSMutableSet<NSString *> *revealedKeys;
@property (nonatomic, copy, nullable) NSString *renderedBundleID;
@property (nonatomic, weak, nullable) CDRProgressBarView *paneProgressBar;
@property (nonatomic, weak, nullable) NSTextField *paneProgressLabel;
@property (nonatomic) BOOL progressActive;
@property (nonatomic) double progressFraction;
@property (nonatomic, copy, nullable) NSString *progressDetail;
@end

@implementation CDRDetailViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _allRowModels = @[];
    _expandedKeys = [NSMutableSet set];
    _revealedKeys = [NSMutableSet set];
    return self;
}

- (void)loadView {
    CDRSurfaceView *root = [CDRSurfaceView surfaceWithFill:CDRPalette.surface];
    root.translatesAutoresizingMaskIntoConstraints = YES;
    root.frame = NSMakeRect(0, 0, 1024, 720);

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    self.contentStack = stack;

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

    NSView *centered = [[NSView alloc] initWithFrame:NSZeroRect];
    centered.translatesAutoresizingMaskIntoConstraints = NO;
    centered.hidden = YES;
    self.centeredContainer = centered;

    [root addSubview:scroll];
    [root addSubview:centered];

    NSLayoutConstraint *preferredWidth =
        [stack.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-2 * kSideInset];
    preferredWidth.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [centered.topAnchor constraintEqualToAnchor:root.topAnchor],
        [centered.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [centered.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [centered.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],

        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:28],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:kSideInset],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:kMaxContentWidth],
        preferredWidth,
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-40],
    ]];

    self.view = root;
    [self reload];
}

#pragma mark - Inputs

- (void)setRowModel:(CDRAppRowModel *)rowModel { _rowModel = rowModel; [self reloadIfLoaded]; }
- (void)setAllRowModels:(NSArray<CDRAppRowModel *> *)rows { _allRowModels = [rows copy]; [self reloadIfLoaded]; }
- (void)setLastCheckDate:(NSDate *)date { _lastCheckDate = date; [self reloadIfLoaded]; }
- (void)setOnShowOverrides:(void (^)(NSString *, NSView *))block { _onShowOverrides = [block copy]; [self reloadIfLoaded]; }

- (void)reloadIfLoaded {
    if (self.isViewLoaded) [self reload];
}

- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(NSString *)detail {
    self.progressActive = active;
    self.progressFraction = fraction;
    self.progressDetail = detail;
    self.paneProgressBar.fraction = active ? fraction : 0;
    if (detail.length > 0) self.paneProgressLabel.stringValue = detail;
}

#pragma mark - Rebuild

- (void)reload {
    [self view];
    for (NSView *view in [self.contentStack.arrangedSubviews copy]) {
        [self.contentStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSView *view in [self.centeredContainer.subviews copy]) [view removeFromSuperview];
    self.paneProgressBar = nil;
    self.paneProgressLabel = nil;

    CDRAppRowModel *row = self.rowModel;
    NSPoint savedOrigin = self.scrollView.contentView.bounds.origin;
    BOOL sameApp = row && [row.bundleID isEqualToString:self.renderedBundleID];
    self.renderedBundleID = row.bundleID;

    if (!row) {
        self.scrollView.hidden = YES;
        self.centeredContainer.hidden = NO;
        [self buildNoSelectionPane];
        return;
    }
    self.scrollView.hidden = NO;
    self.centeredContainer.hidden = YES;

    switch (row.state) {
        case CDRAppRowStateRetracted:
        case CDRAppRowStateRecalled:
            [self buildRetractionPaneForRow:row];
            break;
        case CDRAppRowStateDeferred:
            [self addHeaderForRow:row];
            [self buildDeferredPaneForRow:row];
            break;
        default:
            [self addHeaderForRow:row];
            [self addNetworkRowForRow:row];
            [self addStateCardForRow:row];
            [self addReleasesForRow:row];
            break;
    }

    // A refresh of the same app keeps the reader's place; a new app starts
    // at the top.
    [self.view layoutSubtreeIfNeeded];
    NSPoint origin = sameApp ? savedOrigin : NSZeroPoint;
    CGFloat maxY = MAX(0, NSHeight(self.scrollView.documentView.frame) - NSHeight(self.scrollView.contentView.bounds));
    origin.y = MIN(MAX(origin.y, 0), maxY);
    [self.scrollView.contentView scrollToPoint:origin];
    [self.scrollView reflectScrolledClipView:self.scrollView.contentView];
}

- (void)addSection:(NSView *)view spacingBefore:(CGFloat)spacing {
    NSView *last = self.contentStack.arrangedSubviews.lastObject;
    [self addFullWidthView:view toStack:self.contentStack];
    if (last) [self.contentStack setCustomSpacing:spacing afterView:last];
}

/// Every section spans the pane: a stack view only aligns its children, it
/// does not stretch them.
- (void)addFullWidthView:(NSView *)view toStack:(NSStackView *)stack {
    [stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

#pragma mark - Small builders

static NSFont *BodyFont(void) { return [NSFont systemFontOfSize:14]; }

- (NSStackView *)horizontalStack:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = spacing;
    stack.alignment = NSLayoutAttributeCenterY;
    return stack;
}

- (NSStackView *)verticalStack:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = spacing;
    stack.alignment = NSLayoutAttributeLeading;
    return stack;
}

- (NSView *)flexibleSpacer {
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spacer;
}

- (NSImageView *)iconViewForRow:(CDRAppRowModel *)row size:(CGFloat)size {
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [[NSWorkspace sharedWorkspace] iconForFile:row.appURL.path];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:size],
        [icon.heightAnchor constraintEqualToConstant:size],
    ]];
    return icon;
}

/// A button that sends one row action for the selected app.
- (CDRButton *)actionButton:(NSString *)title style:(CDRButtonStyle)style action:(CDRAppRowActions)action {
    CDRButton *button = [CDRButton buttonWithTitle:title style:style target:self action:@selector(rowActionClicked:)];
    button.tag = (NSInteger)action;
    return button;
}

- (void)rowActionClicked:(NSButton *)sender {
    NSString *bundleID = self.rowModel.bundleID;
    if (bundleID && self.onRowAction) self.onRowAction(bundleID, (CDRAppRowActions)sender.tag);
}

/// An underlined text link (the "Show" in "2 security fixes hidden · Show").
- (NSButton *)linkWithTitle:(NSString *)title action:(SEL)action identifier:(nullable NSString *)identifier {
    NSButton *link = [NSButton buttonWithTitle:title target:self action:action];
    link.translatesAutoresizingMaskIntoConstraints = NO;
    link.bordered = NO;
    link.identifier = identifier;
    link.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: CDRPalette.textPrimary,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
    }];
    [link setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return link;
}

/// A rounded card holding a glyph + title line and a wrapped body.
- (NSView *)cardWithSymbol:(NSString *)symbol title:(NSString *)title body:(NSString *)body {
    CDRSurfaceView *card = [CDRSurfaceView cardWithFill:CDRPalette.cardSurface border:CDRPalette.hairline radius:12];
    NSImageView *glyph = CDRSymbolView(symbol, 15, NSFontWeightSemibold, CDRPalette.textPrimary);
    NSTextField *titleLabel = CDRLabel(title, [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold],
                                       CDRPalette.textPrimary, NO);
    NSTextField *bodyLabel = CDRLabel(body, [NSFont systemFontOfSize:13.5], CDRPalette.textSecondary, YES);
    NSStackView *titleRow = [self horizontalStack:@[glyph, titleLabel] spacing:8];
    NSStackView *stack = [self verticalStack:@[titleRow, bodyLabel] spacing:10];
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22],
        [bodyLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
    return card;
}

/// A right-aligned row of buttons under a card.
- (NSView *)buttonRow:(NSArray<NSView *> *)buttons {
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:[self flexibleSpacer]];
    [views addObjectsFromArray:buttons];
    return [self horizontalStack:views spacing:8];
}

static NSString *MediumDate(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;
    return [formatter stringFromDate:date];
}

static NSString *ShortDay(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setLocalizedDateFormatFromTemplate:@"MMMd"];
    return [formatter stringFromDate:date];
}

#pragma mark - Header

- (void)addHeaderForRow:(CDRAppRowModel *)row {
    NSImageView *icon = [self iconViewForRow:row size:64];

    NSTextField *name = CDRLabel(row.appName, [NSFont systemFontOfSize:22 weight:NSFontWeightBold],
                                 CDRPalette.textPrimary, NO);
    NSMutableArray<NSView *> *textRows = [NSMutableArray arrayWithObject:name];
    if (row.developerName.length > 0) {
        [textRows addObject:CDRLabel(row.developerName, [NSFont systemFontOfSize:14], CDRPalette.textSecondary, NO)];
    }

    NSMutableArray<NSView *> *meta = [NSMutableArray array];
    [meta addObject:CDRLabel(row.versionPairDisplay, CDRMonoFont(13, NSFontWeightMedium), CDRPalette.textPrimary, NO)];
    NSFont *metaFont = [NSFont systemFontOfSize:13];
    if (row.advertisedVersion) {
        if (row.artifactSize) {
            NSString *size = [NSByteCountFormatter stringFromByteCount:row.artifactSize.longLongValue
                                                            countStyle:NSByteCountFormatterCountStyleFile];
            [meta addObject:CDRLabel(size, metaFont, CDRPalette.textSecondary, NO)];
        }
        if (row.releaseDate) {
            [meta addObject:CDRLabel([@"Released " stringByAppendingString:MediumDate(row.releaseDate)],
                                     metaFont, CDRPalette.textSecondary, NO)];
        }
        if (row.includedVersions.count > 0) {
            NSString *includes = [@"Includes " stringByAppendingString:
                                  [row.includedVersions componentsJoinedByString:@", "]];
            [meta addObject:CDRLabel(includes, metaFont, CDRPalette.textSecondary, NO)];
        }
    }
    NSStackView *metaRow = [self horizontalStack:meta spacing:14];
    [textRows addObject:metaRow];
    NSStackView *text = [self verticalStack:textRows spacing:3];
    [text setCustomSpacing:8 afterView:textRows[textRows.count - 2]];

    CDRButton *override = [CDRButton iconButtonWithSymbolName:@"slider.horizontal.3"
                                           accessibilityLabel:@"Settings for this app"
                                                       target:self
                                                       action:@selector(overridesClicked:)];
    override.enabled = (self.onShowOverrides != nil);

    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithArray:@[icon, text, [self flexibleSpacer], override]];
    NSString *title = nil;
    CDRAppRowActions action = CDRPrimaryActionForRow(row, &title);
    if (action != CDRAppRowActionNone && title) {
        // Checking and cancelling are quiet; only a real install is the dark pill.
        BOOL quiet = (action == CDRAppRowActionCheckNow || action == CDRAppRowActionCancelPending);
        CDRButton *primary = [self actionButton:title
                                          style:quiet ? CDRButtonStyleSecondary : CDRButtonStylePrimary
                                         action:action];
        if (!quiet) primary.keyEquivalent = @"\r";
        [views addObject:primary];
    }

    NSStackView *header = [self horizontalStack:views spacing:10];
    header.alignment = NSLayoutAttributeTop;
    [header setCustomSpacing:16 afterView:icon];
    [self addSection:header spacingBefore:0];
}

- (void)overridesClicked:(NSButton *)sender {
    NSString *bundleID = self.rowModel.bundleID;
    if (bundleID && self.onShowOverrides) self.onShowOverrides(bundleID, sender);
}

#pragma mark - NETWORK row

/// One line saying what the app may do on the network — and, once a new
/// build has been verified and inspected, how that build compares. When the
/// developer ships an Internet Access Policy the row expands to it.
- (void)addNetworkRowForRow:(CDRAppRowModel *)row {
    NSColor *tone = CDRPalette.textSecondary;
    NSString *symbol = @"globe";
    switch (row.networkTone) {
        case CDRNetworkRowTonePositive: tone = CDRPalette.positiveText; break;
        case CDRNetworkRowToneAttention: tone = CDRPalette.attentionText; symbol = @"exclamationmark.triangle"; break;
        case CDRNetworkRowToneNeutral: break;
    }
    BOOL hasPolicy = row.networkPolicyRows.count > 0;
    NSString *expandKey = [row.bundleID stringByAppendingString:@"|network"];
    BOOL expanded = hasPolicy && [self.expandedKeys containsObject:expandKey];

    CDRSurfaceView *card = [CDRSurfaceView cardWithFill:CDRPalette.cardSurface border:CDRPalette.hairline radius:10];
    NSTextField *label = CDRLabel(@"", [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
                                  CDRPalette.textSecondary, NO);
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:@"NETWORK" attributes:@{
        NSKernAttributeName: @0.9,
        NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: CDRPalette.textSecondary,
    }];
    NSImageView *glyph = CDRSymbolView(symbol, 13, NSFontWeightMedium, tone);
    NSTextField *status = CDRLabel(row.networkTitle, [NSFont systemFontOfSize:13.5 weight:NSFontWeightSemibold],
                                   tone, NO);
    [status setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *detail = CDRLabel(row.networkDetail, [NSFont systemFontOfSize:13], CDRPalette.textSecondary, NO);
    [detail setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:label, glyph, status, detail,
                                       [self flexibleSpacer], nil];
    if (row.networkTrailing.length > 0) {
        NSTextField *trailing = CDRLabel(row.networkTrailing, [NSFont systemFontOfSize:12.5],
                                         CDRPalette.textSecondary, NO);
        [trailing setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
        [views addObject:trailing];
    }
    if (hasPolicy) {
        NSImageView *chevron = CDRSymbolView(expanded ? @"chevron.down" : @"chevron.right", 10.5, NSFontWeightBold,
                                             CDRPalette.textSecondary);
        [views addObject:chevron];
    }
    NSStackView *line = [self horizontalStack:views spacing:8];
    [line setCustomSpacing:16 afterView:label];
    [card addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
        [line.heightAnchor constraintEqualToConstant:20],
        [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
    ]];
    NSLayoutYAxisAnchor *bottom = line.bottomAnchor;

    if (hasPolicy) {
        // The whole line toggles the policy, like a skipped version's row.
        NSButton *toggle = [NSButton buttonWithTitle:@"" target:self action:@selector(skippedToggled:)];
        toggle.translatesAutoresizingMaskIntoConstraints = NO;
        toggle.bordered = NO;
        toggle.transparent = YES;
        toggle.identifier = expandKey;
        [toggle setAccessibilityLabel:expanded ? @"Hide the Internet Access Policy"
                                               : @"Show the Internet Access Policy"];
        [card addSubview:toggle];
        [NSLayoutConstraint activateConstraints:@[
            [toggle.topAnchor constraintEqualToAnchor:card.topAnchor],
            [toggle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [toggle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [toggle.heightAnchor constraintEqualToConstant:36],
        ]];
    }

    NSMutableArray<NSView *> *extra = [NSMutableArray array];
    if (expanded) {
        [extra addObject:CDRLabel(@"Internet Access Policy · from the developer",
                                  [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
                                  CDRPalette.textPrimary, NO)];
        for (CDRInternetAccessPolicyRow *policyRow in row.networkPolicyRows) {
            NSTextField *subject = CDRLabel(policyRow.subject, CDRMonoFont(12, NSFontWeightRegular),
                                            CDRPalette.textPrimary, YES);
            NSString *purposeText = (row.exposesDeveloperDetail && policyRow.transport)
                ? [NSString stringWithFormat:@"%@  (%@%@)", policyRow.purpose, policyRow.transport,
                   policyRow.incoming ? @", incoming" : @""]
                : policyRow.purpose;
            NSTextField *purpose = CDRLabel(purposeText, [NSFont systemFontOfSize:13], CDRPalette.textPrimary, YES);
            NSStackView *pair = [self horizontalStack:@[subject, purpose] spacing:14];
            pair.alignment = NSLayoutAttributeTop;
            [subject.widthAnchor constraintEqualToConstant:190].active = YES;
            [extra addObject:pair];
        }
    }
    for (NSString *developerLine in row.networkDeveloperLines) {
        NSTextField *mono = CDRLabel(developerLine, CDRMonoFont(11.5, NSFontWeightRegular),
                                     CDRPalette.textSecondary, NO);
        mono.selectable = YES;
        [extra addObject:mono];
    }
    if (extra.count > 0) {
        CDRHairlineView *rule = [[CDRHairlineView alloc] initWithFrame:NSZeroRect];
        NSStackView *stack = [self verticalStack:extra spacing:8];
        [card addSubview:rule];
        [card addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [rule.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:8],
            [rule.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [rule.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:rule.bottomAnchor constant:10],
            [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        ]];
        bottom = stack.bottomAnchor;
        [bottom constraintEqualToAnchor:card.bottomAnchor constant:-12].active = YES;
    } else {
        [bottom constraintEqualToAnchor:card.bottomAnchor constant:-8].active = YES;
    }
    [self addSection:card spacingBefore:22];
}

#pragma mark - State cards (rows that still show notes)

- (void)addStateCardForRow:(CDRAppRowModel *)row {
    switch (row.state) {
        case CDRAppRowStateStoppedAtMajor: {
            NSString *version = row.advertisedVersion ?: @"This";
            NSView *card = [self cardWithSymbol:@"arrow.up.to.line"
                                          title:[NSString stringWithFormat:@"%@ is a major version", version]
                                           body:[NSString stringWithFormat:
                @"You stop at major versions, so %@ stays installed until you choose.", row.installedVersion]];
            [self addSection:card spacingBefore:18];
            // Writes a per-app override, so this app stops stopping.
            CDRButton *always = [self actionButton:@"Always allow for this app"
                                             style:CDRButtonStyleSecondary
                                            action:CDRAppRowActionAlwaysAllowMajor];
            always.enabled = (row.actions & CDRAppRowActionAlwaysAllowMajor) != 0;
            CDRButton *install = [self actionButton:[NSString stringWithFormat:@"Install %@", version]
                                              style:CDRButtonStylePrimary action:CDRAppRowActionInstall];
            install.enabled = (row.actions & CDRAppRowActionInstall) != 0;
            [self addSection:[self buttonRow:@[always, install]] spacingBefore:14];
            break;
        }
        case CDRAppRowStateInspecting:
            [self addProgressPaneWithTitle:@"Downloading to inspect…"
                                     steps:@[@"Download", @"Verify Team ID",
                                             [NSString stringWithFormat:@"Compare entitlements with %@", row.installedVersion],
                                             @"Ready to decide"]
                              currentIndex:[self stepIndexForPhase:row.operationPhase inspecting:YES]
                                    footer:@"Conductor checks a build's entitlements before you're asked to install it."];
            break;
        case CDRAppRowStateWorking:
            [self addProgressPaneWithTitle:[row shortStateLineAsOf:[NSDate date]]
                                     steps:@[@"Download", @"Verify Team ID", @"Install"]
                              currentIndex:[self stepIndexForPhase:row.operationPhase inspecting:NO]
                                    footer:nil];
            break;
        case CDRAppRowStateWaitingForQuit: {
            NSView *card = [self cardWithSymbol:@"hourglass"
                                          title:[NSString stringWithFormat:@"Installs when you quit %@", row.appName]
                                           body:@"The new build is downloaded and verified. Nothing changes until the app quits on its own."];
            [self addSection:card spacingBefore:18];
            break;
        }
        case CDRAppRowStateCheckFailed: {
            NSView *card = [self cardWithSymbol:@"exclamationmark.circle"
                                          title:@"Couldn't check for updates"
                                           body:row.errorDescription ?: @"The last check didn't finish."];
            [self addSection:card spacingBefore:18];
            if (row.actions & CDRAppRowActionVendorSite) {
                [self addSection:[self buttonRow:@[[self actionButton:@"Developer's Site"
                                                                style:CDRButtonStyleSecondary
                                                               action:CDRAppRowActionVendorSite]]]
                   spacingBefore:14];
            }
            break;
        }
        case CDRAppRowStateIgnored: {
            NSView *card = [self cardWithSymbol:@"eye.slash"
                                          title:@"Ignored"
                                           body:@"Scheduled checks skip this app. Checking it by hand still works."];
            [self addSection:card spacingBefore:18];
            [self addSection:[self buttonRow:@[[self actionButton:@"Check now" style:CDRButtonStyleSecondary
                                                           action:CDRAppRowActionCheckNow]]]
               spacingBefore:14];
            break;
        }
        case CDRAppRowStateSkipped: {
            NSString *version = row.advertisedVersion ?: @"This version";
            NSView *card = [self cardWithSymbol:@"forward"
                                          title:[NSString stringWithFormat:@"You skipped %@", version]
                                           body:[NSString stringWithFormat:
                @"%@ stays installed. Conductor will tell you about the next version; checking this app now brings %@ back.",
                row.installedVersion, version]];
            [self addSection:card spacingBefore:18];
            break;
        }
        case CDRAppRowStateUpToDate: {
            NSString *text = [NSString stringWithFormat:@"%@ %@ is the latest version.", row.appName, row.installedVersion];
            [self addSection:CDRLabel(text, BodyFont(), CDRPalette.textSecondary, YES) spacingBefore:24];
            break;
        }
        case CDRAppRowStateUnknown:
            [self addSection:CDRLabel(@"Conductor hasn't checked this app yet.", BodyFont(),
                                      CDRPalette.textSecondary, YES)
               spacingBefore:24];
            break;
        default:
            break;
    }
}

- (NSInteger)stepIndexForPhase:(CDRUpdatePhase)phase inspecting:(BOOL)inspecting {
    switch (phase) {
        case CDRUpdatePhaseIdle:
        case CDRUpdatePhaseFetching:
        case CDRUpdatePhaseDownloading:
            return 0;
        case CDRUpdatePhaseExtracting:
        case CDRUpdatePhaseVerifying:
            return 1;
        case CDRUpdatePhaseInspecting:
            return 2;
        default:
            // An install is past inspection; an inspect-ahead is ready.
            return inspecting ? 3 : 2;
    }
}

- (void)addProgressPaneWithTitle:(NSString *)title
                           steps:(NSArray<NSString *> *)steps
                    currentIndex:(NSInteger)currentIndex
                          footer:(nullable NSString *)footer {
    NSTextField *titleLabel = CDRLabel(self.progressDetail.length > 0 ? self.progressDetail : title,
                                       [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],
                                       CDRPalette.textPrimary, NO);
    CDRProgressBarView *bar = [[CDRProgressBarView alloc] initWithFrame:NSZeroRect];
    bar.fraction = self.progressActive ? self.progressFraction : -1;
    self.paneProgressBar = bar;
    self.paneProgressLabel = titleLabel;

    NSMutableArray<NSView *> *rows = [NSMutableArray arrayWithObjects:titleLabel, bar, nil];
    for (NSUInteger i = 0; i < steps.count; i++) {
        BOOL done = (NSInteger)i < currentIndex;
        BOOL current = (NSInteger)i == currentIndex;
        NSString *symbol = done ? @"checkmark" : (current ? @"arrow.right" : @"circle");
        NSColor *color = (done || current) ? CDRPalette.textPrimary : CDRPalette.textSecondary;
        NSImageView *glyph = CDRSymbolView(symbol, 10.5, NSFontWeightSemibold, color);
        [glyph.widthAnchor constraintEqualToConstant:16].active = YES;
        NSTextField *label = CDRLabel(steps[i],
                                      [NSFont systemFontOfSize:13.5 weight:current ? NSFontWeightSemibold : NSFontWeightRegular],
                                      color, NO);
        [rows addObject:[self horizontalStack:@[glyph, label] spacing:8]];
    }
    if (footer) [rows addObject:CDRLabel(footer, [NSFont systemFontOfSize:12.5], CDRPalette.textSecondary, YES)];

    NSStackView *stack = [self verticalStack:rows spacing:9];
    [stack setCustomSpacing:8 afterView:titleLabel];
    [stack setCustomSpacing:16 afterView:bar];
    if (footer) [stack setCustomSpacing:18 afterView:rows[rows.count - 2]];
    [bar.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [self addSection:stack spacingBefore:22];
}

#pragma mark - Deferred pane

- (void)buildDeferredPaneForRow:(CDRAppRowModel *)row {
    NSDate *now = [NSDate date];
    NSString *title = @"Deferred";
    NSTimeInterval left = [row.deferredUntil timeIntervalSinceDate:now];
    if (row.deferredUntil && left > 0) {
        NSInteger days = (NSInteger)ceil(left / 86400.0);
        title = left < 86400.0 ? @"Deferred for less than a day"
              : [NSString stringWithFormat:@"Deferred for %ld more %@", (long)days, days == 1 ? @"day" : @"days"];
    }
    NSString *version = row.advertisedVersion ?: @"The new build";
    NSString *wait = row.deferralDurationName
        ? [NSString stringWithFormat:@"You wait %@ before new builds show up.", row.deferralDurationName]
        : @"Your update settings hold new builds for a while before they show up.";
    NSString *body = row.deferredUntil
        ? [NSString stringWithFormat:@"%@ %@ appears on %@.", wait, version, ShortDay(row.deferredUntil)]
        : wait;
    [self addSection:[self cardWithSymbol:@"clock" title:title body:body] spacingBefore:22];

    // "Update now" is the user's consent to take this build out of deferral
    // (deferral.md break-through); "Keep waiting" changes nothing.
    CDRButton *keep = [CDRButton buttonWithTitle:@"Keep waiting" style:CDRButtonStyleSecondary
                                          target:self action:@selector(keepWaitingClicked:)];
    CDRButton *update = [self actionButton:@"Update now" style:CDRButtonStylePrimary
                                    action:CDRAppRowActionInstallDeferred];
    update.enabled = (row.actions & CDRAppRowActionInstallDeferred) != 0;
    [self addSection:[self buttonRow:@[keep, update]] spacingBefore:14];
}

- (void)keepWaitingClicked:(id)sender {
    // Deliberately nothing: the deferral stands.
}

#pragma mark - Retraction pane

- (void)buildRetractionPaneForRow:(CDRAppRowModel *)row {
    BOOL recalled = (row.state == CDRAppRowStateRecalled);
    NSString *version = row.retractedVersion ?: @"an update";

    CDRSurfaceView *banner = [CDRSurfaceView cardWithFill:CDRPalette.attentionFill
                                                   border:CDRPalette.attentionBorder radius:12];
    NSImageView *glyph = CDRSymbolView(@"arrow.uturn.backward", 22, NSFontWeightSemibold, CDRPalette.attentionText);
    NSTextField *title = CDRLabel([NSString stringWithFormat:recalled ? @"Developer recalled %@" : @"Developer retracted %@",
                                   version],
                                  [NSFont systemFontOfSize:19 weight:NSFontWeightBold], CDRPalette.attentionText, NO);
    NSTextField *subtitle = CDRLabel(recalled ? @"You have the recalled build installed." : @"You have the latest build.",
                                     [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold],
                                     CDRPalette.attentionText, NO);
    NSStackView *bannerText = [self verticalStack:@[title, subtitle] spacing:2];
    NSStackView *bannerRow = [self horizontalStack:@[glyph, bannerText] spacing:16];
    [banner addSubview:bannerRow];
    [NSLayoutConstraint activateConstraints:@[
        [bannerRow.topAnchor constraintEqualToAnchor:banner.topAnchor constant:22],
        [bannerRow.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-22],
        [bannerRow.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:24],
        [bannerRow.trailingAnchor constraintLessThanOrEqualToAnchor:banner.trailingAnchor constant:-24],
    ]];
    [self addSection:banner spacingBefore:0];

    NSImageView *icon = [self iconViewForRow:row size:36];
    NSTextField *name = CDRLabel(row.appName, [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
                                 CDRPalette.textPrimary, NO);
    NSString *versions = recalled
        ? [NSString stringWithFormat:@"%@ installed · recalled", row.installedVersion]
        : [NSString stringWithFormat:@"%@ installed · %@ withdrawn", row.installedVersion, version];
    NSTextField *versionLine = CDRLabel(versions, CDRMonoFont(12, NSFontWeightRegular), CDRPalette.textSecondary, NO);
    NSStackView *appRow = [self horizontalStack:@[icon, [self verticalStack:@[name, versionLine] spacing:2]] spacing:12];
    [self addSection:appRow spacingBefore:22];

    NSString *body = recalled
        ? [NSString stringWithFormat:@"The developer pulled %@ after you installed it. Conductor doesn't downgrade automatically — check the developer's site for guidance.", version]
        : ((row.retractionAdvertisedDate && row.retractionPulledDate)
           ? [NSString stringWithFormat:@"%@ was advertised on %@ and pulled on %@. There's nothing to install.",
              version, ShortDay(row.retractionAdvertisedDate), ShortDay(row.retractionPulledDate)]
           : [NSString stringWithFormat:@"%@ was advertised, then pulled. There's nothing to install.", version]);
    [self addSection:CDRLabel(body, BodyFont(), CDRPalette.textSecondary, YES) spacingBefore:16];

    NSMutableArray<NSView *> *buttons = [NSMutableArray array];
    if (row.actions & CDRAppRowActionVendorSite) {
        [buttons addObject:[self actionButton:@"Developer's Site" style:CDRButtonStyleSecondary
                                       action:CDRAppRowActionVendorSite]];
    }
    if (row.actions & CDRAppRowActionAcknowledge) {
        CDRButton *gotIt = [self actionButton:@"Got it" style:CDRButtonStylePrimary action:CDRAppRowActionAcknowledge];
        gotIt.keyEquivalent = @"\r";
        [buttons addObject:gotIt];
    }
    if (buttons.count > 0) [self addSection:[self buttonRow:buttons] spacingBefore:24];
}

#pragma mark - Release notes

- (void)addReleasesForRow:(CDRAppRowModel *)row {
    NSArray<CDRRelease *> *releases = row.releases;
    if (releases.count == 0) return;

    [self addReleaseHeadingForRelease:releases.firstObject];
    [self addGroupsForRelease:releases.firstObject row:row intoStack:nil];

    for (NSUInteger i = 1; i < releases.count; i++) {
        [self addSkippedRelease:releases[i] row:row spacingBefore:(i == 1 ? 28 : 10)];
    }
}

- (void)addReleaseHeadingForRelease:(CDRRelease *)release {
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    [views addObject:CDRLabel(release.version, [NSFont systemFontOfSize:16 weight:NSFontWeightBold],
                              CDRPalette.textPrimary, NO)];
    if (release.date) {
        [views addObject:CDRLabel(MediumDate(release.date), [NSFont systemFontOfSize:13],
                                  CDRPalette.textSecondary, NO)];
    }
    [views addObject:[self flexibleSpacer]];
    NSStackView *heading = [self horizontalStack:views spacing:10];
    heading.alignment = NSLayoutAttributeFirstBaseline;
    [self addSection:heading spacingBefore:26];
    [self addSection:[[CDRHairlineView alloc] initWithFrame:NSZeroRect] spacingBefore:10];
}

/// One row of the notes table: a fixed-width leading column (badge or dot)
/// and the content beside it. A badge hangs from the top of the row beside
/// the first note; a lone dot (`centered`) sits on the text line.
- (NSView *)noteRowWithLeading:(NSView *)leading content:(NSView *)content centered:(BOOL)centered {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:leading];
    [row addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [leading.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:centered ? 5 : 0],
        centered ? [leading.centerYAnchor constraintEqualToAnchor:content.centerYAnchor]
                 : [leading.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],
        [content.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kBadgeColumnWidth],
        [content.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:row.topAnchor constant:13],
        [content.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-13],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
    ]];
    return row;
}

/// The grouped notes of one release. Appends to `stack` when given (a
/// skipped version's card), otherwise to the pane itself.
- (void)addGroupsForRelease:(CDRRelease *)release row:(CDRAppRowModel *)row intoStack:(nullable NSStackView *)stack {
    void (^add)(NSView *) = ^(NSView *view) {
        if (stack) [self addFullWidthView:view toStack:stack];
        else [self addSection:view spacingBefore:0];
    };

    NSArray<CDRReleaseNoteGroup *> *groups = release.groups;
    for (CDRReleaseNoteGroup *group in groups) {
        NSString *revealKey = [NSString stringWithFormat:@"%@|%@|%@", row.bundleID, release.version,
                               CDRReleaseNoteTypeKey(group.type)];
        BOOL shown = CDRReleaseNoteTypeSetContains(row.shownTypes, group.type)
            || [self.revealedKeys containsObject:revealKey];

        if (shown) {
            NSMutableArray<NSView *> *items = [NSMutableArray array];
            for (CDRReleaseNote *note in group.notes) {
                NSTextField *label = CDRLabel(note.text, BodyFont(), CDRPalette.textPrimary, YES);
                label.selectable = YES;
                [items addObject:label];
            }
            NSStackView *itemStack = [self verticalStack:items spacing:8];
            for (NSView *item in items) [item.widthAnchor constraintEqualToAnchor:itemStack.widthAnchor].active = YES;
            add([self noteRowWithLeading:[[CDRBadgeView alloc] initWithType:group.type]
                                 content:itemStack centered:NO]);
        } else {
            // Collapsed to a count; the dot keeps the category visible.
            CDRCategoryDotsView *dot = [[CDRCategoryDotsView alloc]
                initWithTypes:CDRReleaseNoteTypeSetWithType(group.type)];
            NSString *text = [NSString stringWithFormat:@"%@ hidden  ·",
                              CDRReleaseNoteTypeCountPhrase(group.type, group.notes.count)];
            NSTextField *label = CDRLabel(text, BodyFont(), CDRPalette.textSecondary, NO);
            NSButton *show = [self linkWithTitle:@"Show" action:@selector(revealClicked:) identifier:revealKey];
            NSStackView *content = [self horizontalStack:@[label, show, [self flexibleSpacer]] spacing:6];
            add([self noteRowWithLeading:dot content:content centered:YES]);
        }
        add([[CDRHairlineView alloc] initWithFrame:NSZeroRect]);
    }

    if (release.undisplayableNoteCount > 0) {
        NSString *text = [NSString stringWithFormat:@"%lu %@ this Conductor can't display",
                          (unsigned long)release.undisplayableNoteCount,
                          release.undisplayableNoteCount == 1 ? @"note" : @"notes"];
        add([self footnoteRowWithText:text changelogURL:row.changelogURL]);
    } else if (groups.count == 0) {
        add([self footnoteRowWithText:@"The developer didn't include notes for this version"
                         changelogURL:row.changelogURL]);
    }
}

- (NSView *)footnoteRowWithText:(NSString *)text changelogURL:(nullable NSURL *)changelogURL {
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    [views addObject:CDRLabel(changelogURL ? [text stringByAppendingString:@"  ·"] : [text stringByAppendingString:@"."],
                              BodyFont(), CDRPalette.textSecondary, NO)];
    if (changelogURL) {
        [views addObject:[self linkWithTitle:@"See changelog" action:@selector(changelogClicked:) identifier:nil]];
    }
    [views addObject:[self flexibleSpacer]];
    NSStackView *content = [self horizontalStack:views spacing:6];
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kBadgeColumnWidth],
        [content.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:row.topAnchor constant:13],
        [content.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-13],
    ]];
    return row;
}

- (void)revealClicked:(NSButton *)sender {
    if (sender.identifier) [self.revealedKeys addObject:sender.identifier];
    [self reload];
}

- (void)changelogClicked:(id)sender {
    NSURL *url = self.rowModel.changelogURL;
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

/// A skipped intermediate version: one collapsed line (version, date, dots,
/// note count) that expands to its own grouped notes.
- (void)addSkippedRelease:(CDRRelease *)release row:(CDRAppRowModel *)row spacingBefore:(CGFloat)spacing {
    NSString *key = [NSString stringWithFormat:@"%@|%@", row.bundleID, release.version];
    BOOL expanded = [self.expandedKeys containsObject:key];

    CDRSurfaceView *card = [CDRSurfaceView cardWithFill:CDRPalette.cardSurface border:CDRPalette.hairline radius:10];

    NSImageView *chevron = CDRSymbolView(expanded ? @"chevron.down" : @"chevron.right", 10.5, NSFontWeightBold,
                                         CDRPalette.textPrimary);
    [chevron.widthAnchor constraintEqualToConstant:14].active = YES;
    NSTextField *version = CDRLabel(release.version, [NSFont systemFontOfSize:15 weight:NSFontWeightBold],
                                    CDRPalette.textPrimary, NO);
    NSString *when = release.date ? [NSString stringWithFormat:@"%@ · skipped", MediumDate(release.date)] : @"skipped";
    NSTextField *date = CDRLabel(when, [NSFont systemFontOfSize:13], CDRPalette.textSecondary, NO);
    CDRCategoryDotsView *dots = [[CDRCategoryDotsView alloc] initWithTypes:release.typeSet];
    NSString *countText = [NSString stringWithFormat:@"%lu %@", (unsigned long)release.notes.count,
                           release.notes.count == 1 ? @"note" : @"notes"];
    NSTextField *count = CDRLabel(countText, [NSFont systemFontOfSize:13], CDRPalette.textSecondary, NO);
    NSStackView *line = [self horizontalStack:@[chevron, version, date, dots, [self flexibleSpacer], count] spacing:10];
    [line setCustomSpacing:14 afterView:date];

    // The whole line is the control: a transparent button over it carries the
    // click, the keyboard focus and the accessibility label.
    NSButton *toggle = [NSButton buttonWithTitle:@"" target:self action:@selector(skippedToggled:)];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.bordered = NO;
    toggle.transparent = YES;
    toggle.identifier = key;
    [toggle setAccessibilityLabel:[NSString stringWithFormat:@"%@ version %@, skipped, %@",
                                   expanded ? @"Collapse" : @"Expand", release.version, countText]];

    [card addSubview:line];
    [card addSubview:toggle];
    [NSLayoutConstraint activateConstraints:@[
        [line.topAnchor constraintEqualToAnchor:card.topAnchor constant:11],
        [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [line.heightAnchor constraintEqualToConstant:20],
        [toggle.topAnchor constraintEqualToAnchor:card.topAnchor],
        [toggle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [toggle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [toggle.heightAnchor constraintEqualToConstant:42],
    ]];

    if (expanded) {
        NSStackView *groups = [[NSStackView alloc] initWithFrame:NSZeroRect];
        groups.translatesAutoresizingMaskIntoConstraints = NO;
        groups.orientation = NSUserInterfaceLayoutOrientationVertical;
        groups.alignment = NSLayoutAttributeLeading;
        groups.spacing = 0;
        [self addFullWidthView:[[CDRHairlineView alloc] initWithFrame:NSZeroRect] toStack:groups];
        [self addGroupsForRelease:release row:row intoStack:groups];
        [card addSubview:groups];
        [NSLayoutConstraint activateConstraints:@[
            [groups.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:11],
            [groups.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [groups.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [groups.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-4],
        ]];
    } else {
        [line.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-11].active = YES;
    }
    [self addSection:card spacingBefore:spacing];
}

- (void)skippedToggled:(NSButton *)sender {
    NSString *key = sender.identifier;
    if (!key) return;
    if ([self.expandedKeys containsObject:key]) [self.expandedKeys removeObject:key];
    else [self.expandedKeys addObject:key];
    [self reload];
}

#pragma mark - Nothing selected

- (void)buildNoSelectionPane {
    NSImageView *glyph = nil;
    NSString *title = nil;
    NSTextField *body = nil;
    CDRButton *button = nil;

    if (self.allRowModels.count == 0) {
        glyph = CDRSymbolView(@"shippingbox", 30, NSFontWeightRegular, CDRPalette.textSecondary);
        title = @"No Conductor-ready apps";
        body = CDRLabel(@"", [NSFont systemFontOfSize:13.5], CDRPalette.textSecondary, YES);
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:
            @"Conductor looks for a conductor.json inside each app in /Applications and ~/Applications. None of yours ship one yet."
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13.5],
                         NSForegroundColorAttributeName: CDRPalette.textSecondary}];
        NSRange mono = [text.string rangeOfString:@"conductor.json"];
        [text addAttributes:@{NSFontAttributeName: CDRMonoFont(12.5, NSFontWeightMedium),
                              NSForegroundColorAttributeName: CDRPalette.textPrimary} range:mono];
        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.alignment = NSTextAlignmentCenter;
        [text addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, text.length)];
        body.attributedStringValue = text;
        button = [CDRButton buttonWithTitle:@"Scan again" style:CDRButtonStyleSecondary
                                     target:self action:@selector(scanAgainClicked:)];
    } else if (CDRAllRowsUpToDate(self.allRowModels)) {
        glyph = CDRSymbolView(@"checkmark.circle", 30, NSFontWeightRegular, CDRPalette.positiveText);
        title = @"Everything's up to date";
        NSString *apps = [NSString stringWithFormat:@"%lu %@", (unsigned long)self.allRowModels.count,
                          self.allRowModels.count == 1 ? @"app" : @"apps"];
        NSString *checked = CDRCheckedAgoString(self.lastCheckDate, [NSDate date]).lowercaseString;
        body = CDRLabel([NSString stringWithFormat:@"%@ · %@", apps, checked],
                        [NSFont systemFontOfSize:13.5], CDRPalette.textSecondary, YES);
        body.alignment = NSTextAlignmentCenter;
        button = [CDRButton buttonWithTitle:@"Check now" style:CDRButtonStyleSecondary
                                     target:self action:@selector(checkAllClicked:)];
    } else {
        glyph = CDRSymbolView(@"sidebar.left", 26, NSFontWeightRegular, CDRPalette.textSecondary);
        title = @"Select an app";
        body = CDRLabel(@"Its update and the developer's notes appear here.",
                        [NSFont systemFontOfSize:13.5], CDRPalette.textSecondary, YES);
        body.alignment = NSTextAlignmentCenter;
    }

    NSTextField *titleLabel = CDRLabel(title, [NSFont systemFontOfSize:17 weight:NSFontWeightBold],
                                       CDRPalette.textPrimary, NO);
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObjects:glyph, titleLabel, body, nil];
    if (button) [views addObject:button];
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 8;
    [stack setCustomSpacing:14 afterView:glyph];
    if (button) [stack setCustomSpacing:18 afterView:body];

    [self.centeredContainer addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.centeredContainer.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.centeredContainer.centerYAnchor constant:-20],
        [body.widthAnchor constraintLessThanOrEqualToConstant:330],
    ]];
}

- (void)scanAgainClicked:(id)sender {
    if (self.onScanAgain) self.onScanAgain();
}

- (void)checkAllClicked:(id)sender {
    if (self.onCheckAll) self.onCheckAll();
}

@end
