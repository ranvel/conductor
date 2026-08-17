//
//  CDRStatusWindowController.h
//  Conductor
//

#import <Cocoa/Cocoa.h>
#import "CDRAppRowModel.h"

@class CDRDevModeSession;

NS_ASSUME_NONNULL_BEGIN

/// The windowed UI: renders the shared per-app row models (the same array the
/// menu bar renders) and forwards row actions. A first-class surface — some
/// users want a windowed app, not another menu bar resident; that choice is
/// theirs. The activity log lives in its own window (CDRLogWindowController).
@interface CDRStatusWindowController : NSWindowController

- (instancetype)initWithSession:(CDRDevModeSession *)session;

/// The rows to display; assign on the main thread. Selection survives the
/// reload (keyed by bundle ID, not row index).
@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;

/// The bottom progress row. fraction < 0 means indeterminate. active == NO
/// hides the contents but keeps the row's height so the window doesn't jump.
- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(nullable NSString *)detail;

/// Row action chosen by the user (buttons or the row's context menu).
@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
/// Check All — the global sweep, which never breaks through a deferral.
@property (nonatomic, copy, nullable) void (^onCheckAll)(void);

@end

NS_ASSUME_NONNULL_END
