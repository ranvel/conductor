//
//  CDRDetailViewController.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The main window's right pane. For a selected app: header, NETWORK row,
/// and the developer's notes grouped by type; or, when there is no ordinary
/// update to read, the state pane for that row (deferred, retracted,
/// inspecting, stopped at a major version, …). With nothing selected: "no
/// apps" or "everything's up to date".
///
/// Renders only from the row model and the few values below — it never
/// reaches into the update controller.
@interface CDRDetailViewController : NSViewController

/// The selected row, or nil.
@property (nonatomic, nullable) CDRAppRowModel *rowModel;
/// Every row, for the no-selection panes.
@property (nonatomic, copy) NSArray<CDRAppRowModel *> *allRowModels;
@property (nonatomic, nullable) NSDate *lastCheckDate;
/// Categories shown in full; the rest collapse to a one-line count with a
/// "Show" link. Defaults to everything (CND-4 feeds the user's choice).
@property (nonatomic) CDRReleaseNoteTypeSet shownTypes;

@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
@property (nonatomic, copy, nullable) void (^onCheckAll)(void);
@property (nonatomic, copy, nullable) void (^onScanAgain)(void);
/// The per-app override button. Disabled while nil (CND-4 provides it).
@property (nonatomic, copy, nullable) void (^onShowOverrides)(NSString *bundleID, NSView *anchor);

/// Feeds the progress bar of an in-flight pane without rebuilding it.
- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(nullable NSString *)detail;

/// Rebuilds the pane from the current properties. Setting a property does
/// this already; call it when only the clock has moved.
- (void)reload;

@end

NS_ASSUME_NONNULL_END
