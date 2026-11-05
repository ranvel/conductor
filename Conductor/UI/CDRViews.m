//
//  CDRViews.m
//  Conductor
//

#import "CDRViews.h"
#import "CDRPalette.h"

#pragma mark - CDRSurfaceView

@implementation CDRSurfaceView

+ (instancetype)surfaceWithFill:(NSColor *)fill {
    CDRSurfaceView *view = [[self alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.fillColor = fill;
    return view;
}

+ (instancetype)cardWithFill:(NSColor *)fill border:(NSColor *)border radius:(CGFloat)radius {
    CDRSurfaceView *view = [self surfaceWithFill:fill];
    view.borderColor = border;
    view.cornerRadius = radius;
    return view;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _borderWidth = 1;
    return self;
}

- (void)setFillColor:(NSColor *)fillColor { _fillColor = fillColor; self.needsDisplay = YES; }
- (void)setBorderColor:(NSColor *)borderColor { _borderColor = borderColor; self.needsDisplay = YES; }
- (void)setCornerRadius:(CGFloat)cornerRadius { _cornerRadius = cornerRadius; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat inset = self.borderColor ? self.borderWidth / 2.0 : 0;
    NSRect rect = NSInsetRect(self.bounds, inset, inset);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect
                                                         xRadius:self.cornerRadius
                                                         yRadius:self.cornerRadius];
    if (self.fillColor) {
        [self.fillColor setFill];
        [path fill];
    }
    if (self.borderColor) {
        [self.borderColor setStroke];
        path.lineWidth = self.borderWidth;
        [path stroke];
    }
}

@end

#pragma mark - CDRHairlineView

@implementation CDRHairlineView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heightAnchor constraintEqualToConstant:1].active = YES;
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [CDRPalette.hairline setFill];
    NSRectFill(self.bounds);
}

@end

#pragma mark - CDRFlippedView

@implementation CDRFlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - CDRButton

@interface CDRButton ()
@property (nonatomic, nullable) NSString *symbolName;
@end

@implementation CDRButton

+ (instancetype)buttonWithTitle:(NSString *)title style:(CDRButtonStyle)style target:(id)target action:(SEL)action {
    CDRButton *button = [[self alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = title;
    button.style = style;
    button.target = target;
    button.action = action;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    [button setButtonType:NSButtonTypeMomentaryChange];
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [button setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

+ (instancetype)iconButtonWithSymbolName:(NSString *)symbolName
                      accessibilityLabel:(NSString *)label
                                  target:(id)target
                                  action:(SEL)action {
    CDRButton *button = [self buttonWithTitle:@"" style:CDRButtonStyleSecondary target:target action:action];
    button.symbolName = symbolName;
    button.toolTip = label;
    [button setAccessibilityLabel:label];
    return button;
}

- (void)setStyle:(CDRButtonStyle)style { _style = style; self.needsDisplay = YES; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.needsDisplay = YES; }

- (NSDictionary *)titleAttributes {
    NSColor *color = (self.style == CDRButtonStylePrimary) ? CDRPalette.buttonPrimaryText : CDRPalette.textPrimary;
    return @{NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
             NSForegroundColorAttributeName: color};
}

- (NSSize)intrinsicContentSize {
    if (self.symbolName) return NSMakeSize(30, 30);
    NSSize text = [self.title sizeWithAttributes:[self titleAttributes]];
    return NSMakeSize(ceil(text.width) + 30, 30);
}

- (void)drawRect:(NSRect)dirtyRect {
    BOOL pressed = self.isHighlighted;
    CGFloat alpha = self.isEnabled ? (pressed ? 0.78 : 1.0) : 0.4;
    NSRect rect = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:7 yRadius:7];

    if (self.style == CDRButtonStylePrimary) {
        [[CDRPalette.buttonPrimaryFill colorWithAlphaComponent:alpha] setFill];
        [path fill];
    } else {
        [[CDRPalette.buttonSecondaryFill colorWithAlphaComponent:alpha] setFill];
        [path fill];
        [CDRPalette.hairline setStroke];
        path.lineWidth = 1;
        [path stroke];
    }

    if (self.symbolName) {
        NSImage *image = CDRSymbol(self.symbolName, 13, NSFontWeightMedium);
        NSColor *ink = [CDRPalette.textPrimary colorWithAlphaComponent:alpha];
        image = [image imageWithSymbolConfiguration:
                 [NSImageSymbolConfiguration configurationWithPaletteColors:@[ink]]];
        NSSize size = image.size;
        [image drawInRect:NSMakeRect(NSMidX(self.bounds) - size.width / 2, NSMidY(self.bounds) - size.height / 2,
                                     size.width, size.height)];
        return;
    }

    NSMutableDictionary *attributes = [[self titleAttributes] mutableCopy];
    attributes[NSForegroundColorAttributeName] =
        [attributes[NSForegroundColorAttributeName] colorWithAlphaComponent:alpha];
    NSSize text = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(NSMidX(self.bounds) - text.width / 2,
                                        NSMidY(self.bounds) - text.height / 2)
             withAttributes:attributes];
}

@end

#pragma mark - CDRBadgeView

static const CGFloat kBadgeHeight = 22;
static const CGFloat kBadgeGlyphSize = 9.5;

@implementation CDRBadgeView

- (instancetype)initWithType:(CDRReleaseNoteType)type {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _type = type;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityStaticTextRole];
    [self setAccessibilityLabel:CDRReleaseNoteTypeDisplayName(type)];
    return self;
}

- (void)setType:(CDRReleaseNoteType)type {
    _type = type;
    [self setAccessibilityLabel:CDRReleaseNoteTypeDisplayName(type)];
    [self invalidateIntrinsicContentSize];
    self.needsDisplay = YES;
}

- (NSFont *)labelFont { return [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold]; }

- (NSSize)intrinsicContentSize {
    NSSize text = [CDRReleaseNoteTypeDisplayName(self.type)
                   sizeWithAttributes:@{NSFontAttributeName: [self labelFont]}];
    // 9 leading + glyph column (14) + 5 gap + label + 9 trailing.
    return NSMakeSize(ceil(text.width) + 9 + 14 + 5 + 9, kBadgeHeight);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *ink = [CDRPalette inkColorForType:self.type];
    NSColor *fill = [CDRPalette fillColorForType:self.type];
    NSRect rect = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:6 yRadius:6];
    if (fill) {
        [fill setFill];
        [path fill];
    } else {
        // Conductor-generated: a dashed outline, never a filled badge.
        CGFloat dash[] = {3, 2.5};
        [path setLineDash:dash count:2 phase:0];
        path.lineWidth = 1;
        [ink setStroke];
        [path stroke];
    }

    NSImage *glyph = [CDRSymbol([CDRPalette symbolNameForType:self.type], kBadgeGlyphSize, NSFontWeightBold)
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[ink]]];
    NSSize glyphSize = glyph.size;
    [glyph drawInRect:NSMakeRect(9 + (14 - glyphSize.width) / 2, NSMidY(self.bounds) - glyphSize.height / 2,
                                 glyphSize.width, glyphSize.height)];

    NSDictionary *attributes = @{NSFontAttributeName: [self labelFont], NSForegroundColorAttributeName: ink};
    NSString *label = CDRReleaseNoteTypeDisplayName(self.type);
    NSSize text = [label sizeWithAttributes:attributes];
    [label drawAtPoint:NSMakePoint(9 + 14 + 5, NSMidY(self.bounds) - text.height / 2) withAttributes:attributes];
}

@end

#pragma mark - CDRCategoryDotsView

static const CGFloat kDotDiameter = 7;
static const CGFloat kDotGap = 3.5;

@implementation CDRCategoryDotsView

- (instancetype)initWithTypes:(CDRReleaseNoteTypeSet)types {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _types = types;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self updateAccessibility];
    return self;
}

- (void)setTypes:(CDRReleaseNoteTypeSet)types {
    _types = types;
    [self updateAccessibility];
    [self invalidateIntrinsicContentSize];
    self.needsDisplay = YES;
}

- (NSUInteger)dotCount {
    NSUInteger count = 0;
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        if (CDRReleaseNoteTypeSetContains(self.types, (CDRReleaseNoteType)i)) count++;
    }
    return count;
}

- (void)updateAccessibility {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        if (CDRReleaseNoteTypeSetContains(self.types, (CDRReleaseNoteType)i)) {
            [names addObject:CDRReleaseNoteTypeDisplayName((CDRReleaseNoteType)i)];
        }
    }
    [self setAccessibilityElement:names.count > 0];
    [self setAccessibilityRole:NSAccessibilityStaticTextRole];
    [self setAccessibilityLabel:[names componentsJoinedByString:@", "]];
}

- (NSSize)intrinsicContentSize {
    NSUInteger count = [self dotCount];
    if (count == 0) return NSMakeSize(0, kDotDiameter);
    return NSMakeSize(count * kDotDiameter + (count - 1) * kDotGap, kDotDiameter);
}

- (void)drawRect:(NSRect)dirtyRect {
    CGFloat x = 0;
    CGFloat y = NSMidY(self.bounds) - kDotDiameter / 2;
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)i;
        if (!CDRReleaseNoteTypeSetContains(self.types, type)) continue;
        NSColor *ink = [CDRPalette inkColorForType:type];
        NSRect dot = NSMakeRect(x, y, kDotDiameter, kDotDiameter);
        if (type == CDRReleaseNoteTypeRetracted) {
            NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dot, 0.75, 0.75)];
            ring.lineWidth = 1.5;
            [ink setStroke];
            [ring stroke];
        } else {
            [ink setFill];
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
        x += kDotDiameter + kDotGap;
    }
}

@end

#pragma mark - CDRProgressBarView

@implementation CDRProgressBarView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heightAnchor constraintEqualToConstant:4].active = YES;
    return self;
}

- (void)setFraction:(double)fraction {
    _fraction = fraction;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    CGFloat radius = NSHeight(bounds) / 2;
    [CDRPalette.progressTrack setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] fill];

    // Indeterminate work shows a fixed partial fill rather than an animation:
    // the step list beside it says what is happening.
    double fraction = self.fraction < 0 ? 0.33 : MIN(MAX(self.fraction, 0), 1);
    if (fraction <= 0) return;
    NSRect filled = bounds;
    filled.size.width = MAX(NSHeight(bounds), NSWidth(bounds) * fraction);
    [CDRPalette.buttonPrimaryFill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:filled xRadius:radius yRadius:radius] fill];
}

@end

#pragma mark - Helpers

NSTextField *CDRLabel(NSString *text, NSFont *font, NSColor *color, BOOL wraps) {
    NSTextField *label = wraps ? [NSTextField wrappingLabelWithString:text ?: @""]
                               : [NSTextField labelWithString:text ?: @""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.selectable = NO;
    if (wraps) {
        [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    } else {
        label.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    return label;
}

NSFont *CDRMonoFont(CGFloat size, NSFontWeight weight) {
    return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

NSImage *CDRSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    return [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
}

NSImageView *CDRSymbolView(NSString *name, CGFloat pointSize, NSFontWeight weight, NSColor *color) {
    NSImageView *view = [[NSImageView alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.image = CDRSymbol(name, pointSize, weight);
    view.contentTintColor = color;
    view.imageScaling = NSImageScaleNone;
    [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}
