//
//  CDRPalette.m
//  Conductor
//

#import "CDRPalette.h"

/// A named asset color, or `fallback` if the catalog entry is ever missing —
/// a wrong shade is better than a nil color reaching AppKit.
static NSColor *Named(NSString *name, NSColor *fallback) {
    return [NSColor colorNamed:name] ?: fallback;
}

@implementation CDRPalette

+ (NSColor *)surface { return Named(@"Surface", NSColor.textBackgroundColor); }
+ (NSColor *)sidebarSurface { return Named(@"SidebarSurface", NSColor.windowBackgroundColor); }
+ (NSColor *)titleBarSurface { return Named(@"TitleBarSurface", NSColor.windowBackgroundColor); }
+ (NSColor *)cardSurface { return Named(@"CardSurface", NSColor.controlBackgroundColor); }
+ (NSColor *)rowSelection { return Named(@"RowSelection", NSColor.unemphasizedSelectedContentBackgroundColor); }
+ (NSColor *)hairline { return Named(@"Hairline", NSColor.separatorColor); }
+ (NSColor *)textPrimary { return Named(@"TextPrimary", NSColor.labelColor); }
+ (NSColor *)textSecondary { return Named(@"TextSecondary", NSColor.secondaryLabelColor); }
+ (NSColor *)buttonPrimaryFill { return Named(@"ButtonPrimaryFill", NSColor.labelColor); }
+ (NSColor *)buttonPrimaryText { return Named(@"ButtonPrimaryText", NSColor.textBackgroundColor); }
+ (NSColor *)buttonSecondaryFill { return Named(@"ButtonSecondaryFill", NSColor.controlColor); }
+ (NSColor *)attentionText { return Named(@"AttentionText", NSColor.systemOrangeColor); }
+ (NSColor *)attentionFill { return Named(@"AttentionFill", NSColor.controlBackgroundColor); }
+ (NSColor *)attentionBorder { return Named(@"AttentionBorder", NSColor.separatorColor); }
+ (NSColor *)positiveText { return Named(@"PositiveText", NSColor.systemGreenColor); }
+ (NSColor *)progressTrack { return Named(@"ProgressTrack", NSColor.separatorColor); }

/// "Notice", "Removed", … — the asset names are keyed by the type's display
/// name, so a new type needs only its two colorsets.
static NSString *AssetStem(CDRReleaseNoteType type) {
    return [@"Badge" stringByAppendingString:CDRReleaseNoteTypeDisplayName(type)];
}

+ (NSColor *)inkColorForType:(CDRReleaseNoteType)type {
    return Named([AssetStem(type) stringByAppendingString:@"Text"], NSColor.labelColor);
}

+ (NSColor *)fillColorForType:(CDRReleaseNoteType)type {
    if (type == CDRReleaseNoteTypeRetracted) return nil;
    return Named([AssetStem(type) stringByAppendingString:@"Fill"], NSColor.controlBackgroundColor);
}

+ (NSString *)symbolNameForType:(CDRReleaseNoteType)type {
    switch (type) {
        case CDRReleaseNoteTypeNotice: return @"exclamationmark";
        case CDRReleaseNoteTypeRemoved: return @"xmark";
        case CDRReleaseNoteTypeDisabled: return @"pause";
        case CDRReleaseNoteTypeSecurity: return @"lock";
        case CDRReleaseNoteTypeAdded: return @"sparkle";
        case CDRReleaseNoteTypeImproved: return @"arrow.up";
        case CDRReleaseNoteTypeFixed: return @"checkmark";
        case CDRReleaseNoteTypeRetracted: return @"arrow.uturn.backward";
    }
    return @"circle";
}

@end
