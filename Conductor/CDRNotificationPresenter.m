//
//  CDRNotificationPresenter.m
//  Conductor
//

#import "CDRNotificationPresenter.h"
#import "CDRUpdatePolicy.h"
#import "CDRSharedLog.h"

NSString * const CDRNotificationCategoryUpdateAvailable = @"CDR_UPDATE_AVAILABLE";
NSString * const CDRNotificationCategoryRetracted = @"CDR_RETRACTED";
NSString * const CDRNotificationCategoryInstalled = @"CDR_INSTALLED";

NSString * const CDRNotificationActionInstall = @"CDR_INSTALL";
NSString * const CDRNotificationActionView = @"CDR_VIEW";
NSString * const CDRNotificationActionVendorSite = @"CDR_VENDOR_SITE";

static NSString * const kBundleIDKey = @"bundleID";
static NSString * const kVendorURLKey = @"vendorURL";

@implementation CDRNotificationPresenter

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    UNNotificationAction *install = [UNNotificationAction actionWithIdentifier:CDRNotificationActionInstall
                                                                         title:@"Install"
                                                                       options:0];
    UNNotificationAction *view = [UNNotificationAction actionWithIdentifier:CDRNotificationActionView
                                                                      title:@"View"
                                                                    options:0];
    UNNotificationAction *vendor = [UNNotificationAction actionWithIdentifier:CDRNotificationActionVendorSite
                                                                        title:@"Developer's Site"
                                                                      options:UNNotificationActionOptionForeground];
    [center setNotificationCategories:[NSSet setWithArray:@[
        [UNNotificationCategory categoryWithIdentifier:CDRNotificationCategoryUpdateAvailable
                                               actions:@[install, view]
                                     intentIdentifiers:@[] options:0],
        [UNNotificationCategory categoryWithIdentifier:CDRNotificationCategoryRetracted
                                               actions:@[vendor]
                                     intentIdentifiers:@[] options:0],
        [UNNotificationCategory categoryWithIdentifier:CDRNotificationCategoryInstalled
                                               actions:@[]
                                     intentIdentifiers:@[] options:0],
    ]]];
    return self;
}

#pragma mark - Authorization

- (void)requestProvisionalAuthorization {
    [[UNUserNotificationCenter currentNotificationCenter]
        requestAuthorizationWithOptions:(UNAuthorizationOptionProvisional | UNAuthorizationOptionAlert |
                                         UNAuthorizationOptionBadge)
                      completionHandler:^(BOOL granted, NSError *error) {
        if (error) [CDRSharedLog log:[NSString stringWithFormat:
            @"Notification authorization (provisional): %@", error.localizedDescription]];
    }];
}

- (void)requestFullAuthorization {
    [[UNUserNotificationCenter currentNotificationCenter]
        requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionBadge)
                      completionHandler:^(BOOL granted, NSError *error) {
        if (!granted) [CDRSharedLog log:
            @"Notifications are off — background check results appear in the menu and window only."];
    }];
}

#pragma mark - Posting

- (void)postUpdateAvailableForAppNamed:(NSString *)appName
                              bundleID:(NSString *)bundleID
                               version:(NSString *)version
                               urgency:(CDRUrgency)urgency {
    NSString *body = [NSString stringWithFormat:@"Version %@ is ready to install.", version];
    if (urgency != CDRUrgencyNone) {
        // The urgency claim is the vendor's, and the copy says so.
        body = [NSString stringWithFormat:@"%@ %@", body,
                CDRUrgencyNoticeCopy(urgency, appName, version)];
    }
    [self postNoticeWithTitle:[NSString stringWithFormat:@"%@ update available", appName]
                         body:body
                     bundleID:bundleID
                      version:version
                     category:CDRNotificationCategoryUpdateAvailable
                    vendorURL:nil];
}

- (void)postNoticeWithTitle:(NSString *)title
                       body:(NSString *)body
                   bundleID:(NSString *)bundleID
                    version:(NSString *)version
                   category:(NSString *)category
                  vendorURL:(NSURL *)vendorURL {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = body;
    content.categoryIdentifier = category;
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[kBundleIDKey] = bundleID;
    if (vendorURL) userInfo[kVendorURLKey] = vendorURL.absoluteString;
    content.userInfo = userInfo;

    NSString *identifier = [NSString stringWithFormat:@"%@|%@|%@", bundleID, version ?: @"-", category];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError *error) {
        if (error) [CDRSharedLog log:[NSString stringWithFormat:
            @"Could not post notification for %@: %@", bundleID, error.localizedDescription]];
    }];
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // A background updater is "foreground" in the technical sense whenever its
    // window is open; banners should still appear.
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    NSString *bundleID = userInfo[kBundleIDKey];
    NSString *vendorString = userInfo[kVendorURLKey];
    NSURL *vendorURL = vendorString ? [NSURL URLWithString:vendorString] : nil;
    NSString *actionIdentifier = response.actionIdentifier;

    if (bundleID && self.onAction) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onAction(bundleID, actionIdentifier, vendorURL);
        });
    }
    completionHandler();
}

@end
