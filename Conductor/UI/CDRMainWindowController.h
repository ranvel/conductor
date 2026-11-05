//
//  CDRMainWindowController.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRAppRowModel.h"

@class CDRDevModeSession;
@class CDRDetailViewController;

NS_ASSUME_NONNULL_BEGIN

/// The v2 main window: the managed apps on the left (≈20%), the selected
/// app's update and the developer's notes on the right. Like the menu bar,
/// it renders exclusively from CDRAppRowModel and sends every click out
/// through a block — it holds no update state of its own.
@interface CDRMainWindowController : NSWindowController

- (instancetype)initWithSession:(CDRDevModeSession *)session;

@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;
/// Feeds "Checked 4 min ago".
@property (nonatomic, nullable) NSDate *lastCheckDate;
/// The selected app. Nil shows the no-selection pane. When the selected app
/// goes away, or nothing was ever chosen, the window picks the first row
/// that needs reading (CDRDefaultSelection).
@property (nonatomic, copy, nullable) NSString *selectedBundleID;

/// The aggregate progress of in-flight operations.
- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(nullable NSString *)detail;

@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
/// Title-bar "Check now" and the up-to-date pane's button.
@property (nonatomic, copy, nullable) void (^onCheckAll)(void);
/// The no-apps pane's "Scan again".
@property (nonatomic, copy, nullable) void (^onScanAgain)(void);
@property (nonatomic, copy, nullable) void (^onOpenSettings)(void);

/// The right pane, for wiring the inputs later tickets add (shown
/// categories, the per-app override popover).
@property (nonatomic, readonly) CDRDetailViewController *detailViewController;

@end

NS_ASSUME_NONNULL_END
