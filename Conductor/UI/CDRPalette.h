//
//  CDRPalette.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRReleaseNote.h"

NS_ASSUME_NONNULL_BEGIN

/// The v2 design's colors (ref-assets/, light + dark). Every value is a named
/// color in Assets.xcassets/Palette so both appearances come from one place
/// and nothing in the UI hard-codes a hex value.
@interface CDRPalette : NSObject

#pragma mark Surfaces and ink

@property (class, nonatomic, readonly) NSColor *surface;            // detail pane
@property (class, nonatomic, readonly) NSColor *sidebarSurface;     // app list
@property (class, nonatomic, readonly) NSColor *titleBarSurface;
@property (class, nonatomic, readonly) NSColor *cardSurface;        // NETWORK row, inner cards
@property (class, nonatomic, readonly) NSColor *rowSelection;
@property (class, nonatomic, readonly) NSColor *hairline;
@property (class, nonatomic, readonly) NSColor *textPrimary;
@property (class, nonatomic, readonly) NSColor *textSecondary;
@property (class, nonatomic, readonly) NSColor *buttonPrimaryFill;
@property (class, nonatomic, readonly) NSColor *buttonPrimaryText;
@property (class, nonatomic, readonly) NSColor *buttonSecondaryFill;
@property (class, nonatomic, readonly) NSColor *attentionText;      // amber
@property (class, nonatomic, readonly) NSColor *attentionFill;
@property (class, nonatomic, readonly) NSColor *attentionBorder;
@property (class, nonatomic, readonly) NSColor *positiveText;       // green
@property (class, nonatomic, readonly) NSColor *progressTrack;

#pragma mark Release-note vocabulary

/// Badge ink, also the category-dot color.
+ (NSColor *)inkColorForType:(CDRReleaseNoteType)type;
/// Badge fill. Nil for Retracted, which is drawn as a dashed outline.
+ (nullable NSColor *)fillColorForType:(CDRReleaseNoteType)type;
/// SF Symbol name for the badge glyph.
+ (NSString *)symbolNameForType:(CDRReleaseNoteType)type;

@end

NS_ASSUME_NONNULL_END
