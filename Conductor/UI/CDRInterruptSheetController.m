//
//  CDRInterruptSheetController.m
//  Conductor
//

#import "CDRInterruptSheetController.h"
#import "CDRPalette.h"
#import "CDRViews.h"

static const CGFloat kSheetWidth = 520;
static const CGFloat kSheetInset = 22;

@interface CDRInterruptSheetController ()
@property (nonatomic, readwrite) CDRInterruptSheetModel *model;
@property (nonatomic) NSStackView *stack;
@property (nonatomic, copy, nullable) void (^completion)(CDRInterruptSheetResponse);
@property (nonatomic, weak, nullable) NSWindow *parentWindow;
@end

@implementation CDRInterruptSheetController

- (instancetype)initWithModel:(CDRInterruptSheetModel *)model {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kSheetWidth, 300)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (!self) return nil;
    _model = model;
    [self buildContent];
    return self;
}

#pragma mark - Small builders

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

- (NSImageView *)appIcon:(CGFloat)size {
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = self.model.appURL ? [[NSWorkspace sharedWorkspace] iconForFile:self.model.appURL.path]
                                   : [NSImage imageNamed:NSImageNameApplicationIcon];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [NSLayoutConstraint activateConstraints:@[[icon.widthAnchor constraintEqualToConstant:size],
                                              [icon.heightAnchor constraintEqualToConstant:size]]];
    return icon;
}

/// Adds a section spanning the sheet's content width.
- (void)addSection:(NSView *)view spacingBefore:(CGFloat)spacing {
    NSView *last = self.stack.arrangedSubviews.lastObject;
    [self.stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:self.stack.widthAnchor].active = YES;
    if (last) [self.stack setCustomSpacing:spacing afterView:last];
}

/// A rounded card with `content` inset inside it.
- (CDRSurfaceView *)cardAround:(NSView *)content fill:(NSColor *)fill border:(NSColor *)border inset:(CGFloat)inset {
    CDRSurfaceView *card = [CDRSurfaceView cardWithFill:fill border:border radius:10];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:inset],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-inset],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:inset],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-inset],
    ]];
    return card;
}

#pragma mark - Build

- (void)buildContent {
    CDRInterruptSheetModel *model = self.model;
    CDRSurfaceView *root = [CDRSurfaceView surfaceWithFill:CDRPalette.surface];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    self.stack = stack;
    [root addSubview:stack];

    NSLayoutYAxisAnchor *top = root.topAnchor;
    CGFloat topInset = kSheetInset;
    if (model.attentionHeader) {
        NSView *banner = [self attentionBanner];
        [root addSubview:banner];
        [NSLayoutConstraint activateConstraints:@[
            [banner.topAnchor constraintEqualToAnchor:root.topAnchor],
            [banner.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
            [banner.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        ]];
        top = banner.bottomAnchor;
        topInset = 18;
    } else {
        [self addPlainHeader];
    }

    if (model.body.length > 0) [self addBody];
    if (model.diffLines.count > 0) [self addDiffBlock];
    if (model.policyRows.count > 0) [self addPolicyTable];
    if (model.noteGroups.count > 0) [self addNotesCard];
    if (model.warning.length > 0) [self addWarningStrip];
    if (model.footnote.length > 0) [self addFootnote];
    [self addFooter];

    [NSLayoutConstraint activateConstraints:@[
        [root.widthAnchor constraintEqualToConstant:kSheetWidth],
        [stack.topAnchor constraintEqualToAnchor:top constant:topInset],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:kSheetInset],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kSheetInset],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-kSheetInset],
    ]];

    self.window.contentView = root;
    [root layoutSubtreeIfNeeded];
    [self.window setContentSize:root.fittingSize];
}

/// Icon, title, subtitle.
- (void)addPlainHeader {
    NSTextField *title = CDRLabel(self.model.title, [NSFont systemFontOfSize:17 weight:NSFontWeightBold],
                                  CDRPalette.textPrimary, YES);
    NSTextField *subtitle = CDRLabel(self.model.subtitle, [NSFont systemFontOfSize:13.5],
                                     CDRPalette.textSecondary, YES);
    NSStackView *text = [self vertical:@[title, subtitle] spacing:3];
    NSStackView *header = [self horizontal:@[[self appIcon:44], text] spacing:14];
    header.alignment = NSLayoutAttributeTop;
    [title.widthAnchor constraintEqualToAnchor:text.widthAnchor].active = YES;
    [self addSection:header spacingBefore:0];
}

/// The amber retraction banner: glyph, title, subtitle, centered.
- (NSView *)attentionBanner {
    CDRSurfaceView *banner = [CDRSurfaceView surfaceWithFill:CDRPalette.attentionFill];
    NSImageView *glyph = CDRSymbolView(@"arrow.uturn.backward", 26, NSFontWeightSemibold, CDRPalette.attentionText);
    NSTextField *title = CDRLabel(self.model.title, [NSFont systemFontOfSize:20 weight:NSFontWeightBold],
                                  CDRPalette.attentionText, NO);
    NSTextField *subtitle = CDRLabel(self.model.subtitle, [NSFont systemFontOfSize:14.5 weight:NSFontWeightSemibold],
                                     CDRPalette.attentionText, NO);
    NSStackView *stack = [NSStackView stackViewWithViews:@[glyph, title, subtitle]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 6;
    [stack setCustomSpacing:14 afterView:glyph];
    CDRSurfaceView *rule = [CDRSurfaceView surfaceWithFill:CDRPalette.attentionBorder];
    [banner addSubview:stack];
    [banner addSubview:rule];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:banner.topAnchor constant:30],
        [stack.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-26],
        [stack.centerXAnchor constraintEqualToAnchor:banner.centerXAnchor],
        [rule.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor],
        [rule.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor],
        [rule.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor],
        [rule.heightAnchor constraintEqualToConstant:1],
    ]];
    return banner;
}

/// The one line of plain explanation, with the app's name in bold.
- (void)addBody {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:self.model.body attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13.5],
        NSForegroundColorAttributeName: CDRPalette.textSecondary,
    }];
    if (self.model.bodyEmphasis.length > 0 && [self.model.body hasPrefix:self.model.bodyEmphasis]) {
        [text addAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13.5 weight:NSFontWeightSemibold],
                              NSForegroundColorAttributeName: CDRPalette.textPrimary}
                      range:NSMakeRange(0, self.model.bodyEmphasis.length)];
    }
    NSTextField *label = CDRLabel(@"", [NSFont systemFontOfSize:13.5], CDRPalette.textSecondary, YES);
    label.attributedStringValue = text;
    NSStackView *row = [self horizontal:@[[self appIcon:32], label] spacing:12];
    row.alignment = NSLayoutAttributeTop;
    [self addSection:row spacingBefore:0];
}

/// "ENTITLEMENTS · 0.4 → 0.5" over monospace + / − lines.
- (void)addDiffBlock {
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    NSTextField *heading = CDRLabel(@"", [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
                                    CDRPalette.textSecondary, NO);
    heading.attributedStringValue = [[NSAttributedString alloc] initWithString:self.model.diffHeading ?: @"" attributes:@{
        NSKernAttributeName: @0.9,
        NSFontAttributeName: [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: CDRPalette.textSecondary,
    }];
    [rows addObject:heading];
    for (CDRInterruptSheetDiffLine *line in self.model.diffLines) {
        NSString *text = [NSString stringWithFormat:@"%@ %@", line.added ? @"+" : @"−", line.text];
        NSColor *ink = line.added ? CDRPalette.positiveText : [CDRPalette inkColorForType:CDRReleaseNoteTypeRemoved];
        NSTextField *label = CDRLabel(text, CDRMonoFont(12.5, NSFontWeightRegular), ink, NO);
        label.selectable = YES;
        [rows addObject:label];
    }
    NSStackView *stack = [self vertical:rows spacing:7];
    [self addSection:[self cardAround:stack fill:CDRPalette.cardSurface border:CDRPalette.hairline inset:12]
       spacingBefore:16];
}

/// The developer's Internet Access Policy: a title row, then where → why.
- (void)addPolicyTable {
    CDRSurfaceView *card = [CDRSurfaceView cardWithFill:CDRPalette.surface border:CDRPalette.hairline radius:10];

    CDRSurfaceView *headerFill = [CDRSurfaceView surfaceWithFill:CDRPalette.cardSurface];
    headerFill.cornerRadius = 10;
    NSImageView *glyph = CDRSymbolView(@"doc.text", 12, NSFontWeightMedium, CDRPalette.textPrimary);
    NSTextField *title = CDRLabel(@"Internet Access Policy", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                                  CDRPalette.textPrimary, NO);
    NSTextField *source = CDRLabel(@"· from the developer", [NSFont systemFontOfSize:12.5],
                                   CDRPalette.textSecondary, NO);
    NSStackView *header = [self horizontal:@[glyph, title, source] spacing:7];
    [card addSubview:headerFill];
    [card addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [headerFill.topAnchor constraintEqualToAnchor:card.topAnchor constant:1],
        [headerFill.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:1],
        [headerFill.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-1],
        [headerFill.heightAnchor constraintEqualToConstant:35],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [header.centerYAnchor constraintEqualToAnchor:headerFill.centerYAnchor],
    ]];

    NSLayoutYAxisAnchor *top = headerFill.bottomAnchor;
    for (CDRInterruptSheetPolicyRow *row in self.model.policyRows) {
        CDRHairlineView *line = [[CDRHairlineView alloc] initWithFrame:NSZeroRect];
        NSTextField *subject = CDRLabel(row.subject, CDRMonoFont(12, NSFontWeightRegular), CDRPalette.textPrimary, YES);
        NSTextField *purpose = CDRLabel(row.purpose, [NSFont systemFontOfSize:13], CDRPalette.textPrimary, YES);
        for (NSView *view in @[line, subject, purpose]) [card addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [line.topAnchor constraintEqualToAnchor:top],
            [line.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [subject.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:11],
            [subject.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
            [subject.widthAnchor constraintEqualToConstant:150],
            [purpose.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:10],
            [purpose.leadingAnchor constraintEqualToAnchor:subject.trailingAnchor constant:14],
            [purpose.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        ]];
        // The row is as tall as its taller column.
        NSLayoutGuide *bottom = [[NSLayoutGuide alloc] init];
        [card addLayoutGuide:bottom];
        [NSLayoutConstraint activateConstraints:@[
            [bottom.topAnchor constraintGreaterThanOrEqualToAnchor:subject.bottomAnchor constant:11],
            [bottom.topAnchor constraintGreaterThanOrEqualToAnchor:purpose.bottomAnchor constant:11],
            [bottom.heightAnchor constraintEqualToConstant:0],
        ]];
        NSLayoutConstraint *tight = [bottom.topAnchor constraintEqualToAnchor:line.bottomAnchor];
        tight.priority = NSLayoutPriorityDefaultLow;
        tight.active = YES;
        top = bottom.bottomAnchor;
    }
    [top constraintEqualToAnchor:card.bottomAnchor constant:-1].active = YES;
    [self addSection:card spacingBefore:14];
}

/// The notes that caused the hold: each group's badge above its items.
- (void)addNotesCard {
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    for (CDRReleaseNoteGroup *group in self.model.noteGroups) {
        [rows addObject:[[CDRBadgeView alloc] initWithType:group.type]];
        for (CDRReleaseNote *note in group.notes) {
            NSTextField *label = CDRLabel(note.text, [NSFont systemFontOfSize:13.5], CDRPalette.textPrimary, YES);
            label.selectable = YES;
            [rows addObject:label];
        }
    }
    NSStackView *stack = [self vertical:rows spacing:8];
    for (NSView *row in rows) {
        if ([row isKindOfClass:[NSTextField class]]) {
            [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        }
    }
    [self addSection:[self cardAround:stack fill:CDRPalette.cardSurface border:CDRPalette.hairline inset:14]
       spacingBefore:16];
}

- (void)addWarningStrip {
    NSImageView *glyph = CDRSymbolView(@"exclamationmark.triangle", 12, NSFontWeightSemibold, CDRPalette.attentionText);
    NSTextField *label = CDRLabel(self.model.warning, [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                                  CDRPalette.attentionText, YES);
    NSStackView *row = [self horizontal:@[glyph, label] spacing:8];
    [self addSection:[self cardAround:row fill:CDRPalette.attentionFill border:CDRPalette.attentionBorder inset:11]
       spacingBefore:14];
}

/// "You hold updates that include … items." followed by its link.
- (void)addFootnote {
    NSTextField *label = CDRLabel(self.model.footnote, [NSFont systemFontOfSize:12.5], CDRPalette.textSecondary, YES);
    NSMutableArray<NSView *> *rows = [NSMutableArray arrayWithObject:label];
    if (self.model.linkTitle.length > 0) {
        NSButton *link = [NSButton buttonWithTitle:self.model.linkTitle target:self action:@selector(linkClicked:)];
        link.translatesAutoresizingMaskIntoConstraints = NO;
        link.bordered = NO;
        link.identifier = @"sheet.link";
        link.attributedTitle = [[NSAttributedString alloc] initWithString:self.model.linkTitle attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: CDRPalette.textPrimary,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        }];
        [rows addObject:link];
    }
    NSStackView *stack = [self vertical:rows spacing:3];
    [label.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [self addSection:stack spacingBefore:14];
}

- (void)addFooter {
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:spacer];

    CDRButton *defaultButton = [CDRButton buttonWithTitle:self.model.defaultButton.title style:CDRButtonStylePrimary
                                                   target:self action:@selector(defaultClicked:)];
    defaultButton.identifier = @"sheet.default";
    defaultButton.keyEquivalent = @"\r";

    if (self.model.secondaryButton) {
        CDRButton *secondary = [CDRButton buttonWithTitle:self.model.secondaryButton.title
                                                    style:CDRButtonStyleSecondary
                                                   target:self action:@selector(secondaryClicked:)];
        secondary.identifier = @"sheet.secondary";
        secondary.keyEquivalent = @"\033";   // Escape
        [views addObject:secondary];
    }
    [views addObject:defaultButton];
    [self addSection:[self horizontal:views spacing:8] spacingBefore:20];
    self.window.defaultButtonCell = defaultButton.cell;
    self.window.initialFirstResponder = defaultButton;
}

#pragma mark - Presentation

- (void)beginSheetOnWindow:(NSWindow *)window completion:(void (^)(CDRInterruptSheetResponse))completion {
    self.completion = completion;
    self.parentWindow = window;
    __weak typeof(self) weakSelf = self;
    [window beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
        __strong typeof(weakSelf) self = weakSelf;
        void (^done)(CDRInterruptSheetResponse) = self.completion;
        self.completion = nil;
        if (done) done((CDRInterruptSheetResponse)returnCode);
    }];
}

- (void)endWithResponse:(CDRInterruptSheetResponse)response {
    NSWindow *parent = self.parentWindow ?: self.window.sheetParent;
    if (parent) {
        [parent endSheet:self.window returnCode:(NSModalResponse)response];
        return;
    }
    // Not attached to a window (a test driving the buttons directly).
    void (^done)(CDRInterruptSheetResponse) = self.completion;
    self.completion = nil;
    if (done) done(response);
}

- (void)defaultClicked:(id)sender { [self endWithResponse:CDRInterruptSheetResponseDefault]; }
- (void)secondaryClicked:(id)sender { [self endWithResponse:CDRInterruptSheetResponseSecondary]; }
- (void)linkClicked:(id)sender { [self endWithResponse:CDRInterruptSheetResponseLink]; }

/// Escape on a one-button sheet (retraction) dismisses it.
- (void)cancelOperation:(id)sender {
    [self endWithResponse:CDRInterruptSheetResponseSecondary];
}

@end
