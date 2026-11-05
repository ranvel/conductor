//
//  CDROverridePopoverController.m
//  Conductor
//

#import "CDROverridePopoverController.h"
#import "CDRCategoryGridView.h"
#import "CDRPalette.h"
#import "CDRUpdatePreferences.h"
#import "CDRViews.h"

static const CGFloat kPopoverWidth = 400;
static const CGFloat kPopoverInset = 18;

// Control identifiers, so tests (and VoiceOver users) can find each one.
static NSString * const kDeferControlID = @"override.defer";
static NSString * const kShownControlID = @"override.shown";
static NSString * const kHoldControlID = @"override.hold";
static NSString * const kMajorControlID = @"override.major";

@interface CDROverridePopoverController ()
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, nullable) NSURL *appURL;
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic) NSStackView *stack;
@end

@implementation CDROverridePopoverController

- (instancetype)initWithBundleID:(NSString *)bundleID
                         appName:(NSString *)appName
                          appURL:(NSURL *)appURL
                        defaults:(NSUserDefaults *)defaults {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _bundleID = [bundleID copy];
    _appName = [appName copy];
    _appURL = appURL;
    _defaults = defaults;
    return self;
}

- (void)loadView {
    CDRSurfaceView *root = [CDRSurfaceView surfaceWithFill:CDRPalette.surface];
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    self.stack = stack;
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kPopoverWidth],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:kPopoverInset],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kPopoverInset],
    ]];
    self.view = root;
    [self rebuild];
}

#pragma mark - Model

- (CDRAppPolicyOverride *)override {
    return CDRAppPolicyOverrideForBundleID(self.bundleID, self.defaults);
}

- (void)change:(void (^)(CDRAppPolicyOverride *override))change {
    CDRAppPolicyOverride *override = [self override];
    change(override);
    CDRSetAppPolicyOverride(override, self.bundleID, self.defaults);
    [self rebuild];
    if (self.onChanged) self.onChanged();
}

#pragma mark - Building blocks

- (void)addRow:(NSView *)view spacingBefore:(CGFloat)spacing {
    NSView *last = self.stack.arrangedSubviews.lastObject;
    NSView *padded = [[NSView alloc] initWithFrame:NSZeroRect];
    padded.translatesAutoresizingMaskIntoConstraints = NO;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [padded addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:padded.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:padded.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:padded.leadingAnchor constant:kPopoverInset],
        [view.trailingAnchor constraintLessThanOrEqualToAnchor:padded.trailingAnchor constant:-kPopoverInset],
    ]];
    [self.stack addArrangedSubview:padded];
    [padded.widthAnchor constraintEqualToAnchor:self.stack.widthAnchor].active = YES;
    if (last) [self.stack setCustomSpacing:spacing afterView:last];
}

- (void)addDivider {
    NSView *last = self.stack.arrangedSubviews.lastObject;
    CDRHairlineView *line = [[CDRHairlineView alloc] initWithFrame:NSZeroRect];
    [self.stack addArrangedSubview:line];
    [line.widthAnchor constraintEqualToAnchor:self.stack.widthAnchor].active = YES;
    if (last) [self.stack setCustomSpacing:16 afterView:last];
}

/// "Shown categories" with an OVERRIDDEN tag when the section no longer
/// follows Settings.
- (void)addSectionTitle:(NSString *)title overridden:(BOOL)overridden {
    NSTextField *label = CDRLabel(title, [NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium],
                                  CDRPalette.textPrimary, NO);
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:label];
    if (overridden) {
        CDRSurfaceView *tag = [CDRSurfaceView cardWithFill:nil border:CDRPalette.textSecondary radius:4];
        NSTextField *tagLabel = CDRLabel(@"", [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold],
                                         CDRPalette.textPrimary, NO);
        tagLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:@"OVERRIDDEN" attributes:@{
            NSKernAttributeName: @0.8,
            NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: CDRPalette.textPrimary,
        }];
        [tag addSubview:tagLabel];
        [NSLayoutConstraint activateConstraints:@[
            [tagLabel.topAnchor constraintEqualToAnchor:tag.topAnchor constant:3],
            [tagLabel.bottomAnchor constraintEqualToAnchor:tag.bottomAnchor constant:-3],
            [tagLabel.leadingAnchor constraintEqualToAnchor:tag.leadingAnchor constant:6],
            [tagLabel.trailingAnchor constraintEqualToAnchor:tag.trailingAnchor constant:-6],
        ]];
        tag.identifier = [@"overridden." stringByAppendingString:title];
        [tag setAccessibilityElement:YES];
        [tag setAccessibilityLabel:@"Overridden"];
        [views addObject:tag];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 10;
    row.alignment = NSLayoutAttributeCenterY;
    [self addRow:row spacingBefore:16];
}

- (NSSegmentedControl *)segmentsWithLabels:(NSArray<NSString *> *)labels
                                  selected:(NSInteger)selected
                                identifier:(NSString *)identifier
                                    action:(SEL)action {
    NSSegmentedControl *control = [NSSegmentedControl segmentedControlWithLabels:labels
                                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                         target:self
                                                                         action:action];
    control.identifier = identifier;
    control.selectedSegment = selected;
    return control;
}

- (NSTextField *)echo:(NSString *)text {
    return CDRLabel(text, [NSFont systemFontOfSize:12], CDRPalette.textSecondary, YES);
}

#pragma mark - Rebuild

- (void)rebuild {
    for (NSView *view in [self.stack.arrangedSubviews copy]) {
        [self.stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    CDRUpdatePreferences *global = [CDRUpdatePreferences preferencesFromDefaults:self.defaults];
    CDRAppPolicyOverride *override = [self override];

    // Header.
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = self.appURL ? [[NSWorkspace sharedWorkspace] iconForFile:self.appURL.path] : nil;
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [NSLayoutConstraint activateConstraints:@[[icon.widthAnchor constraintEqualToConstant:32],
                                              [icon.heightAnchor constraintEqualToConstant:32]]];
    NSTextField *name = CDRLabel(self.appName, [NSFont systemFontOfSize:15 weight:NSFontWeightBold],
                                 CDRPalette.textPrimary, NO);
    NSTextField *hint = CDRLabel(@"Anything you don't change follows Settings", [NSFont systemFontOfSize:12],
                                 CDRPalette.textSecondary, NO);
    NSStackView *titles = [NSStackView stackViewWithViews:@[name, hint]];
    titles.orientation = NSUserInterfaceLayoutOrientationVertical;
    titles.alignment = NSLayoutAttributeLeading;
    titles.spacing = 2;
    NSStackView *header = [NSStackView stackViewWithViews:@[icon, titles]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 10;
    [self addRow:header spacingBefore:0];
    [self addDivider];

    // Defer new updates: Follow Settings | Never | 1 week.
    [self addSectionTitle:@"Defer new updates" overridden:(override.soakDuration != nil)];
    NSInteger deferSelection = -1;
    if (!override.soakDuration) deferSelection = 0;
    else if (override.soakDuration.integerValue == CDRSoakDurationOff) deferSelection = 1;
    else if (override.soakDuration.integerValue == CDRSoakDurationOneWeek) deferSelection = 2;
    [self addRow:[self segmentsWithLabels:@[@"Follow Settings", @"Never", @"1 week"]
                                 selected:deferSelection identifier:kDeferControlID
                                   action:@selector(deferChanged:)]
   spacingBefore:8];
    NSString *deferEcho = CDRSettingsEchoForSoakDuration(global.soakDuration);
    if (deferSelection < 0) {
        // A value this control doesn't offer (set some other way): say what it is.
        deferEcho = [NSString stringWithFormat:@"This app: %@ · %@",
                     CDRSoakDurationDisplayName((CDRSoakDuration)override.soakDuration.integerValue), deferEcho];
    }
    [self addRow:[self echo:deferEcho] spacingBefore:8];
    [self addDivider];

    // Shown categories: Follow scheme | Custom.
    [self addSectionTitle:@"Shown categories" overridden:(override.shownTypes != nil)];
    [self addRow:[self segmentsWithLabels:@[@"Follow scheme", @"Custom"]
                                 selected:override.shownTypes ? 1 : 0 identifier:kShownControlID
                                   action:@selector(shownModeChanged:)]
   spacingBefore:8];
    if (override.shownTypes) {
        CDRCategoryGridView *grid = [[CDRCategoryGridView alloc] initWithColumns:4 showsRetracted:NO compact:YES];
        grid.identifier = @"override.shown.grid";
        grid.selectedTypes = override.shownTypes.unsignedIntegerValue;
        __weak typeof(self) weakSelf = self;
        grid.onChange = ^(CDRReleaseNoteTypeSet types) {
            [weakSelf change:^(CDRAppPolicyOverride *o) { o.shownTypes = @(types); }];
        };
        [self addRow:grid spacingBefore:10];
        [self addRow:[self echo:CDRTypeSetOverrideSummary(global.shownTypes, override.shownTypes.unsignedIntegerValue,
                                                         @"shown", @"hidden", self.appName)]
       spacingBefore:10];
    } else {
        [self addRow:[self echo:CDRSettingsEchoForTypeSet(global.shownTypes)] spacingBefore:8];
    }
    [self addDivider];

    // Install manually when…: Follow Settings | Custom.
    [self addSectionTitle:@"Install manually when…" overridden:(override.holdTypes != nil)];
    [self addRow:[self segmentsWithLabels:@[@"Follow Settings", @"Custom"]
                                 selected:override.holdTypes ? 1 : 0 identifier:kHoldControlID
                                   action:@selector(holdModeChanged:)]
   spacingBefore:8];
    if (override.holdTypes) {
        CDRCategoryGridView *grid = [[CDRCategoryGridView alloc] initWithColumns:4 showsRetracted:NO compact:YES];
        grid.identifier = @"override.hold.grid";
        grid.selectedTypes = override.holdTypes.unsignedIntegerValue;
        __weak typeof(self) weakSelf = self;
        grid.onChange = ^(CDRReleaseNoteTypeSet types) {
            [weakSelf change:^(CDRAppPolicyOverride *o) { o.holdTypes = @(types); }];
        };
        [self addRow:grid spacingBefore:10];
        [self addRow:[self echo:CDRTypeSetOverrideSummary(global.holdTypes, override.holdTypes.unsignedIntegerValue,
                                                         @"held", @"not held", self.appName)]
       spacingBefore:10];
    } else {
        [self addRow:[self echo:CDRSettingsEchoForTypeSet(global.holdTypes)] spacingBefore:8];
    }
    [self addDivider];

    // Stop at major versions: Follow Settings | On | Off.
    [self addSectionTitle:@"Stop at major versions" overridden:(override.stopAtMajorVersions != nil)];
    NSInteger majorSelection = !override.stopAtMajorVersions ? 0 : (override.stopAtMajorVersions.boolValue ? 1 : 2);
    [self addRow:[self segmentsWithLabels:@[@"Follow Settings", @"On", @"Off"]
                                 selected:majorSelection identifier:kMajorControlID
                                   action:@selector(majorChanged:)]
   spacingBefore:8];
    [self addRow:[self echo:CDRSettingsEchoForBool(global.stopAtMajorVersions)] spacingBefore:8];
    [self addDivider];

    // Footer.
    NSButton *reset = [NSButton buttonWithTitle:@"Reset to Settings" target:self action:@selector(resetClicked:)];
    reset.bordered = NO;
    reset.identifier = @"override.reset";
    reset.enabled = !override.isEmpty;
    reset.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reset to Settings" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: override.isEmpty ? CDRPalette.textSecondary : CDRPalette.textPrimary,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
    }];
    CDRButton *done = [CDRButton buttonWithTitle:@"Done" style:CDRButtonStylePrimary
                                          target:self action:@selector(doneClicked:)];
    done.keyEquivalent = @"\r";
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *footer = [NSStackView stackViewWithViews:@[reset, spacer, done]];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    [footer.widthAnchor constraintEqualToConstant:kPopoverWidth - 2 * kPopoverInset].active = YES;
    [self addRow:footer spacingBefore:14];
}

#pragma mark - Actions

- (void)deferChanged:(NSSegmentedControl *)sender {
    NSInteger segment = sender.selectedSegment;
    [self change:^(CDRAppPolicyOverride *o) {
        o.soakDuration = segment == 0 ? nil : @(segment == 1 ? CDRSoakDurationOff : CDRSoakDurationOneWeek);
    }];
}

- (void)shownModeChanged:(NSSegmentedControl *)sender {
    BOOL custom = (sender.selectedSegment == 1);
    // Custom starts from what the app shows today, so nothing changes until
    // a checkbox does.
    CDRReleaseNoteTypeSet start = [CDRUpdatePreferences preferencesFromDefaults:self.defaults].shownTypes;
    [self change:^(CDRAppPolicyOverride *o) {
        o.shownTypes = custom ? (o.shownTypes ?: @(start)) : nil;
    }];
}

- (void)holdModeChanged:(NSSegmentedControl *)sender {
    BOOL custom = (sender.selectedSegment == 1);
    CDRReleaseNoteTypeSet start = [CDRUpdatePreferences preferencesFromDefaults:self.defaults].holdTypes;
    [self change:^(CDRAppPolicyOverride *o) {
        o.holdTypes = custom ? (o.holdTypes ?: @(start)) : nil;
    }];
}

- (void)majorChanged:(NSSegmentedControl *)sender {
    NSInteger segment = sender.selectedSegment;
    [self change:^(CDRAppPolicyOverride *o) {
        o.stopAtMajorVersions = segment == 0 ? nil : @(segment == 1);
    }];
}

- (void)resetClicked:(id)sender {
    CDRSetAppPolicyOverride(nil, self.bundleID, self.defaults);
    [self rebuild];
    if (self.onChanged) self.onChanged();
}

- (void)doneClicked:(id)sender {
    if (self.onDone) self.onDone();
}

@end
