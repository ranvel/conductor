//
//  CDRNotificationPresenter.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "CDRManifest.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const CDRNotificationCategoryUpdateAvailable; // Install / View
extern NSString * const CDRNotificationCategoryRetracted;       // Developer's Site
extern NSString * const CDRNotificationCategoryInstalled;       // no actions

extern NSString * const CDRNotificationActionInstall;
extern NSString * const CDRNotificationActionView;
extern NSString * const CDRNotificationActionVendorSite;

/// The passive surface for background results: user notifications, never
/// modals. Authorization is provisional at launch (quiet delivery, no prompt);
/// the full prompt is requested at an earned moment — when the user opts into
/// scheduled checks. Denied authorization degrades to badge + menu/window
/// state, which is acceptable.
@interface CDRNotificationPresenter : NSObject <UNUserNotificationCenterDelegate>

/// actionIdentifier is one of the CDRNotificationAction* constants or
/// UNNotificationDefaultActionIdentifier (a plain tap). Invoked on the main
/// queue.
@property (nonatomic, copy, nullable) void (^onAction)(NSString *bundleID,
                                                       NSString *actionIdentifier,
                                                       NSURL *_Nullable vendorURL);

- (void)requestProvisionalAuthorization;
- (void)requestFullAuthorization;

- (void)postUpdateAvailableForAppNamed:(NSString *)appName
                              bundleID:(NSString *)bundleID
                               version:(NSString *)version
                               urgency:(CDRUrgency)urgency;

/// A re-post with the same bundleID/version/category replaces rather than
/// stacks.
- (void)postNoticeWithTitle:(NSString *)title
                       body:(NSString *)body
                   bundleID:(NSString *)bundleID
                    version:(nullable NSString *)version
                   category:(NSString *)category
                  vendorURL:(nullable NSURL *)vendorURL;

@end

NS_ASSUME_NONNULL_END
