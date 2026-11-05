//
//  CDROverridePopoverController.h
//  Conductor
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The per-app overrides popover, opened from the detail header. Each policy
/// is a "Follow Settings | <values>" control with the current Settings value
/// echoed beneath it; a section that no longer follows Settings is tagged
/// OVERRIDDEN. "Reset to Settings" removes the app's override entirely.
///
/// Storage and UI only: it reads and writes CDRAppPolicyOverride in
/// NSUserDefaults and reports that something changed.
@interface CDROverridePopoverController : NSViewController

- (instancetype)initWithBundleID:(NSString *)bundleID
                         appName:(NSString *)appName
                          appURL:(nullable NSURL *)appURL
                        defaults:(NSUserDefaults *)defaults;

/// The stored override changed (including a reset).
@property (nonatomic, copy, nullable) void (^onChanged)(void);
/// "Done" was pressed.
@property (nonatomic, copy, nullable) void (^onDone)(void);

@end

NS_ASSUME_NONNULL_END
