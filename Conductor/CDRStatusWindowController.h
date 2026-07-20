//
//  CDRStatusWindowController.h
//  Conductor
//

#import <Cocoa/Cocoa.h>
#import "CDRAppRowModel.h"

@class CDRDevModeSession;

NS_ASSUME_NONNULL_BEGIN

/// The windowed UI: renders the shared per-app row models (the same array the
/// menu bar renders), forwards row actions, and shows the activity log. A
/// first-class surface — some users want a windowed app, not another menu bar
/// resident; that choice is theirs.
@interface CDRStatusWindowController : NSWindowController

- (instancetype)initWithSession:(CDRDevModeSession *)session;

/// The rows to display; assign on the main thread.
@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;

/// Row action chosen by the user (buttons or the row's context menu).
@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
/// Check All — the global sweep, which never breaks through a deferral.
@property (nonatomic, copy, nullable) void (^onCheckAll)(void);

@end

NS_ASSUME_NONNULL_END
