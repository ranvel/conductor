//
//  CDRCategoryGridView.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRReleaseNote.h"

NS_ASSUME_NONNULL_BEGIN

/// A grid of checkboxes labelled with the real release-note badges — the
/// control behind "Shown categories" and "Install manually when an update
/// includes…", in Settings and in the per-app popover.
///
/// Retracted is Conductor's own category: when shown it is always checked
/// and always disabled, and it is always part of `selectedTypes`.
@interface CDRCategoryGridView : NSView

/// `showsRetracted` adds the eighth, locked cell (Settings shows it; the
/// narrower per-app popover doesn't). `compact` draws label-only badges
/// closer together, so four still fit across the popover.
- (instancetype)initWithColumns:(NSInteger)columns showsRetracted:(BOOL)showsRetracted compact:(BOOL)compact;

@property (nonatomic) CDRReleaseNoteTypeSet selectedTypes;
@property (nonatomic, getter=isEnabled) BOOL enabled;
/// Called with the new set after the user toggles a checkbox.
@property (nonatomic, copy, nullable) void (^onChange)(CDRReleaseNoteTypeSet types);

/// The checkbox for a type (nil if that type isn't in the grid).
- (nullable NSButton *)checkboxForType:(CDRReleaseNoteType)type;

@end

NS_ASSUME_NONNULL_END
