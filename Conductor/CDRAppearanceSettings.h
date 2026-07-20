//
//  CDRAppearanceSettings.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Where Conductor is visible — both default to YES, both user-configurable
/// (menu-bar residency is the user's choice, not ours). The app must never
/// become invisible: if both read NO (e.g. `defaults write` mischief), the
/// menu bar item wins. Dev mode additionally forces the status item visible
/// for the session, on top of whatever these say (never persisted).
extern NSString * const CDRShowMenuBarItemDefaultsKey;
extern NSString * const CDRShowDockIconDefaultsKey;

BOOL CDRShowMenuBarItemSetting(NSUserDefaults *defaults);
BOOL CDRShowDockIconSetting(NSUserDefaults *defaults);

NS_ASSUME_NONNULL_END
