//
//  CDRViews.h
//  Conductor
//
//  The small drawn pieces the v2 window is assembled from. Everything draws
//  in -drawRect: from CDRPalette's dynamic colors, so light and dark follow
//  the window's appearance with no per-view bookkeeping.
//

#import <AppKit/AppKit.h>
#import "CDRReleaseNote.h"

NS_ASSUME_NONNULL_BEGIN

/// A filled, optionally bordered, optionally rounded rectangle.
@interface CDRSurfaceView : NSView
@property (nonatomic, nullable) NSColor *fillColor;
@property (nonatomic, nullable) NSColor *borderColor;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) CGFloat borderWidth;   // default 1 when borderColor is set
+ (instancetype)surfaceWithFill:(nullable NSColor *)fill;
+ (instancetype)cardWithFill:(nullable NSColor *)fill border:(nullable NSColor *)border radius:(CGFloat)radius;
@end

/// A 1pt horizontal rule in the hairline color.
@interface CDRHairlineView : NSView
@end

/// A top-left-origin container, so scrolled content starts at the top.
@interface CDRFlippedView : NSView
@end

typedef NS_ENUM(NSInteger, CDRButtonStyle) {
    /// Dark filled pill — the one action the pane is asking for.
    CDRButtonStylePrimary = 0,
    /// Outlined, quiet.
    CDRButtonStyleSecondary,
};

/// The design's push button. A real NSButton (target/action, key
/// equivalents, accessibility) that draws its own bezel.
@interface CDRButton : NSButton
@property (nonatomic) CDRButtonStyle style;
+ (instancetype)buttonWithTitle:(NSString *)title
                          style:(CDRButtonStyle)style
                         target:(nullable id)target
                         action:(nullable SEL)action;
/// Square icon button (the settings / override glyph).
+ (instancetype)iconButtonWithSymbolName:(NSString *)symbolName
                      accessibilityLabel:(NSString *)label
                                  target:(nullable id)target
                                  action:(nullable SEL)action;
@end

/// One release-note badge: filled for developer-written types, dashed
/// outline for Retracted. Colors and glyph come from CDRPalette by type.
@interface CDRBadgeView : NSView
@property (nonatomic) CDRReleaseNoteType type;
- (instancetype)initWithType:(CDRReleaseNoteType)type;
@end

/// The trailing run of category dots: one per type in the set, in the fixed
/// order. Retracted is a hollow ring.
@interface CDRCategoryDotsView : NSView
@property (nonatomic) CDRReleaseNoteTypeSet types;
- (instancetype)initWithTypes:(CDRReleaseNoteTypeSet)types;
@end

/// A slim determinate progress bar in the design's ink (indeterminate when
/// `fraction` is negative).
@interface CDRProgressBarView : NSView
@property (nonatomic) double fraction;
@end

#pragma mark - Label and symbol helpers

/// A non-editable label that wraps when `wraps` is YES.
NSTextField *CDRLabel(NSString *text, NSFont *font, NSColor *color, BOOL wraps);
/// The monospaced face used for version pairs and identifiers.
NSFont *CDRMonoFont(CGFloat size, NSFontWeight weight);
/// A template SF Symbol at the given point size and weight.
NSImage * _Nullable CDRSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight);
/// An image view showing `CDRSymbol` tinted with `color`.
NSImageView *CDRSymbolView(NSString *name, CGFloat pointSize, NSFontWeight weight, NSColor *color);

NS_ASSUME_NONNULL_END
