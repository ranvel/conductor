//
//  CDRSettingsWindowController.h
//  Conductor
//

#import <Cocoa/Cocoa.h>
#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The Settings window (M3): launch at login, visibility (menu bar / Dock),
/// deferral duration, scan cadence, and the per-app ignore list. All controls
/// write straight to the durable defaults contracts; the blocks tell the app
/// layer to re-apply what can't be observed lazily.
@interface CDRSettingsWindowController : NSWindowController

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

/// Rows for the ignore list (names + current ignored state); assign on main.
@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;

/// Ignore checkboxes route through the same action path as the other UIs.
@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
@property (nonatomic, copy, nullable) void (^onCadenceChanged)(void);
@property (nonatomic, copy, nullable) void (^onAppearanceChanged)(void);
/// First opt-in to a scheduled cadence — the earned moment for the full
/// notification-permission prompt.
@property (nonatomic, copy, nullable) void (^onRequestFullNotificationAuthorization)(void);

@end

NS_ASSUME_NONNULL_END
