//
//  CDRInterruptSheetController.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRInterruptSheetModel.h"

NS_ASSUME_NONNULL_BEGIN

/// One presentation of an interrupt sheet: builds the view from a
/// CDRInterruptSheetModel and drops it from a window. The same component
/// draws all four variants — header, then whichever optional sections the
/// model carries (badged notes, footnote + link, entitlements diff, policy
/// table, warning strip), then the footer.
///
/// Return activates the default button; Escape the secondary one.
@interface CDRInterruptSheetController : NSWindowController

- (instancetype)initWithModel:(CDRInterruptSheetModel *)model;

@property (nonatomic, readonly) CDRInterruptSheetModel *model;

/// Drops the sheet from `window`. `completion` is called once, after the
/// sheet is dismissed.
- (void)beginSheetOnWindow:(NSWindow *)window
                completion:(void (^)(CDRInterruptSheetResponse response))completion;

/// Ends the sheet as if the user had chosen `response` (also what the
/// buttons call).
- (void)endWithResponse:(CDRInterruptSheetResponse)response;

@end

NS_ASSUME_NONNULL_END
