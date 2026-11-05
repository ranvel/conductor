//
//  CDRSettingsWindowController.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The groups of the Settings form, top to bottom.
typedef NS_ENUM(NSInteger, CDRSettingsSection) {
    CDRSettingsSectionUpdates = 0,
    CDRSettingsSectionWhatYouSee,
    CDRSettingsSectionInstallManually,
    CDRSettingsSectionNetwork,
    CDRSettingsSectionConductor,
    CDRSettingsSectionIgnoredApps,
};

/// The Settings window: one scrolling form. The v2 policy groups (Updates,
/// What you see, Install manually when…, Network) read and write
/// CDRUpdatePreferences; below them, the login item, visibility, check
/// cadence and ignore list from M3, unchanged in behavior.
///
/// Storage and UI only — nothing here acts on a value. Ignore toggles go out
/// through `onRowAction` (the same route as the window and the menu bar).
@interface CDRSettingsWindowController : NSWindowController

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

/// The managed apps, for the ignore list.
@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;

@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);
@property (nonatomic, copy, nullable) void (^onCadenceChanged)(void);
@property (nonatomic, copy, nullable) void (^onAppearanceChanged)(void);
@property (nonatomic, copy, nullable) void (^onRequestFullNotificationAuthorization)(void);
/// Any policy value changed (deferral, major stop, scheme, categories, network).
@property (nonatomic, copy, nullable) void (^onPreferencesChanged)(void);

/// Scrolls the form so `section` is at the top.
- (void)showSection:(CDRSettingsSection)section;

@end

NS_ASSUME_NONNULL_END
