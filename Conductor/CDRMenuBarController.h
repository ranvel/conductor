//
//  CDRMenuBarController.h
//  Conductor
//

#import <Cocoa/Cocoa.h>
#import "CDRAppRowModel.h"

@class CDRDevModeSession;

NS_ASSUME_NONNULL_BEGIN

/// The optional menu bar surface: a status item whose menu renders the same
/// row models the status window renders. The icon carries two signals — an
/// attention variant when any row contributes to the badge, and an unmissable
/// orange dev-mode variant (dev-mode.md) that also forces the item visible
/// for the session regardless of the user's visibility setting.
@interface CDRMenuBarController : NSObject

- (instancetype)initWithSession:(CDRDevModeSession *)session;

/// The rows to render; assign on the main thread. Refreshes icon + badge.
@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;

/// The user's "Show Conductor in the menu bar" setting. Dev mode overrides to
/// visible for the session (never persisted).
@property (nonatomic) BOOL preferredVisible;

@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
/// The global sweep (never breaks through deferrals).
@property (nonatomic, copy, nullable) void (^onCheckAll)(void);
@property (nonatomic, copy, nullable) void (^onOpenWindow)(void);
/// When nil, no Settings item is shown.
@property (nonatomic, copy, nullable) void (^onOpenSettings)(void);

@end

NS_ASSUME_NONNULL_END
