//
//  AppDelegate.m
//  Conductor
//
//  Created by ranvel on 7/19/26.
//

#import "AppDelegate.h"
#import "CDRAppScanner.h"
#import "CDRAppearanceSettings.h"
#import "CDRDevModeSession.h"
#import "CDRManifestFetcher.h"
#import "CDRArtifactStager.h"
#import "CDRMenuBarController.h"
#import "CDRNotificationPresenter.h"
#import "CDRScanScheduler.h"
#import "CDRSettingsWindowController.h"
#import "CDRStatusWindowController.h"
#import "CDRUpdateController.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdateStateStore.h"
#import "CDRSharedLog.h"

@interface AppDelegate () <CDRUpdatePresenting>

@property (strong) IBOutlet NSWindow *window;
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) CDRUpdateController *updateController;
@property (nonatomic) CDRStatusWindowController *statusWindowController;
@property (nonatomic) CDRMenuBarController *menuBarController;
@property (nonatomic) CDRNotificationPresenter *notificationPresenter;
@property (nonatomic) CDRScanScheduler *scanScheduler;
@property (nonatomic, nullable) CDRSettingsWindowController *settingsWindowController;
/// Set while applicationShouldTerminate: is deferred on in-flight operations.
@property (nonatomic) BOOL terminationPending;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // The template xib's window is unused; the status window is programmatic.
    [self.window orderOut:nil];

    NSError *sessionError = nil;
    self.session = [CDRDevModeSession sessionFromArguments:NSProcessInfo.processInfo.arguments
                                                     error:&sessionError];
    if (!self.session) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid arguments";
        alert.informativeText = sessionError.localizedDescription;
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    self.updateController = [[CDRUpdateController alloc]
        initWithSession:self.session
                scanner:[[CDRAppScanner alloc] init]
                fetcher:[[CDRManifestFetcher alloc] initWithSession:self.session]
             stateStore:[CDRUpdateStateStore defaultStore]
               defaults:[NSUserDefaults standardUserDefaults]];
    self.updateController.presenter = self;

    self.statusWindowController = [[CDRStatusWindowController alloc] initWithSession:self.session];
    self.menuBarController = [[CDRMenuBarController alloc] initWithSession:self.session];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [self applyDockIconSetting:CDRShowDockIconSetting(defaults)];
    self.menuBarController.preferredVisible = CDRShowMenuBarItemSetting(defaults);

    __weak typeof(self) weakSelf = self;
    void (^onRowAction)(NSString *, CDRAppRowActions) = ^(NSString *bundleID, CDRAppRowActions action) {
        [weakSelf.updateController performRowAction:action forBundleID:bundleID];
    };
    void (^onCheckAll)(void) = ^{
        [weakSelf.updateController checkAllPassive];
    };
    self.updateController.onRowModelsChanged = ^{
        [weakSelf rowModelsChanged];
    };
    self.statusWindowController.onRowAction = onRowAction;
    self.statusWindowController.onCheckAll = onCheckAll;
    self.menuBarController.onRowAction = onRowAction;
    self.menuBarController.onCheckAll = onCheckAll;
    self.menuBarController.onOpenWindow = ^{
        [weakSelf showStatusWindow];
    };
    self.menuBarController.onOpenSettings = ^{
        [weakSelf showSettingsWindow];
    };
    [self wireAppMenuSettingsItem];

    self.notificationPresenter = [[CDRNotificationPresenter alloc] init];
    [self.notificationPresenter requestProvisionalAuthorization];
    self.notificationPresenter.onAction = ^(NSString *bundleID, NSString *actionIdentifier, NSURL *vendorURL) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if ([actionIdentifier isEqualToString:CDRNotificationActionInstall]) {
            // The tap is consent — the install may legitimately raise the
            // quit prompt. installApp: re-validates against the known
            // manifest; a stale notification degrades to a log line.
            [self.updateController installApp:bundleID];
        } else if ([actionIdentifier isEqualToString:CDRNotificationActionVendorSite] && vendorURL) {
            [[NSWorkspace sharedWorkspace] openURL:vendorURL];
        } else {
            // Plain tap / View: there is no API to open a status-item menu,
            // so the window is the landing surface.
            [self showStatusWindow];
        }
    };

    self.scanScheduler = [[CDRScanScheduler alloc] initWithDefaults:defaults
                                                            handler:^(CDRScanTrigger trigger) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [CDRSharedLog log:[NSString stringWithFormat:@"Passive check (%@).", CDRScanTriggerName(trigger)]];
        [self.scanScheduler noteScanCompletedAt:[NSDate date]];
        [self.updateController rescan];
        [self.updateController checkAllPassive];
    }];
    self.scanScheduler.cadence = CDRScanCadenceFromDefaultsToken(
        [defaults stringForKey:CDRScanCadenceDefaultsKey]);
    if (!self.session.devModeEnabled) {
        // Dev-mode sessions are manual by design; no background cadence.
        [self.scanScheduler start];
    }

    [self cleanStaleStaging];
    [self.updateController rescan];
    [self showStatusWindow];

    if (self.session.devModeEnabled) {
        [CDRSharedLog log:
            [NSString stringWithFormat:@"DEV MODE session for %@ — transport check relaxed for this app only; verification unchanged.",
             self.session.devModeBundleID]];
    }
}

- (void)rowModelsChanged {
    NSArray<CDRAppRowModel *> *rows = self.updateController.rowModels;
    self.statusWindowController.rowModels = rows;
    self.menuBarController.rowModels = rows;
    self.settingsWindowController.rowModels = rows;

    NSUInteger badgeCount = 0;
    for (CDRAppRowModel *row in rows) {
        if (row.contributesToBadge) badgeCount++;
    }
    NSApp.dockTile.badgeLabel = badgeCount ? [@(badgeCount) stringValue] : nil;

    // A deferred quit proceeds once the last critical operation drains.
    if (self.terminationPending && !self.updateController.hasOperationsInCriticalPhase) {
        self.terminationPending = NO;
        [NSApp replyToApplicationShouldTerminate:YES];
    }
}

- (void)showStatusWindow {
    [NSApp activateIgnoringOtherApps:YES];
    [self.statusWindowController showWindow:nil];
    [self.statusWindowController.window makeKeyAndOrderFront:nil];
}

- (void)showSettingsWindow {
    if (!self.settingsWindowController) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        CDRSettingsWindowController *settings =
            [[CDRSettingsWindowController alloc] initWithDefaults:defaults];
        __weak typeof(self) weakSelf = self;
        settings.onRowAction = ^(NSString *bundleID, CDRAppRowActions action) {
            [weakSelf.updateController performRowAction:action forBundleID:bundleID];
        };
        settings.onAppearanceChanged = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self applyDockIconSetting:CDRShowDockIconSetting(defaults)];
            self.menuBarController.preferredVisible = CDRShowMenuBarItemSetting(defaults);
        };
        settings.onCadenceChanged = ^{
            weakSelf.scanScheduler.cadence = CDRScanCadenceFromDefaultsToken(
                [defaults stringForKey:CDRScanCadenceDefaultsKey]);
        };
        settings.onRequestFullNotificationAuthorization = ^{
            [weakSelf.notificationPresenter requestFullAuthorization];
        };
        settings.rowModels = self.updateController.rowModels;
        self.settingsWindowController = settings;
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindowController showWindow:nil];
    [self.settingsWindowController.window makeKeyAndOrderFront:nil];
}

/// The xib's template "Preferences…" item ships with no action; make it the
/// Settings entry point (matching the menu bar item's "Settings…").
- (void)wireAppMenuSettingsItem {
    NSMenu *appMenu = [NSApp.mainMenu itemAtIndex:0].submenu;
    for (NSMenuItem *item in appMenu.itemArray) {
        if ([item.keyEquivalent isEqualToString:@","]) {
            item.title = @"Settings…";
            item.target = self;
            item.action = @selector(settingsMenuItemChosen:);
            return;
        }
    }
}

- (void)settingsMenuItemChosen:(id)sender {
    [self showSettingsWindow];
}

/// Regular (Dock icon) vs accessory is a user setting, applied at launch and
/// whenever Settings toggles it — never hard-coded via LSUIElement.
- (void)applyDockIconSetting:(BOOL)showDockIcon {
    NSApplicationActivationPolicy target = showDockIcon
        ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory;
    if (NSApp.activationPolicy == target) return;
    [NSApp setActivationPolicy:target];
    // Policy switches can drop key-window status; restore it.
    [NSApp activateIgnoringOtherApps:YES];
    [self.statusWindowController.window makeKeyAndOrderFront:nil];
}

/// Staging left behind by a crashed or interrupted run is garbage: the swap is
/// atomic, so anything still in .conductor-staging never made it and never will.
- (void)cleanStaleStaging {
    NSURL *root = [CDRArtifactStager stagingRootNearDestination:
        [NSURL fileURLWithPath:@"/Applications" isDirectory:YES]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:root.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:root error:NULL];
        [CDRSharedLog log:@"Removed stale staging from a previous run."];
    }
}

#pragma mark - CDRUpdatePresenting (modal group — user-initiated flows only)

- (void)presentQuitDecisionForAppNamed:(NSString *)appName
                                 reply:(void (^)(CDRQuitDecision decision))reply {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ is running", appName];
    alert.informativeText = @"The app must quit before Conductor can update it. \"Quit & Update\" may ask you to save unsaved work; \"Update on Quit\" installs whenever you next quit the app yourself.";
    [alert addButtonWithTitle:@"Quit & Update"];
    [alert addButtonWithTitle:@"Update on Quit"];
    [alert addButtonWithTitle:@"Skip"];
    switch ([alert runModal]) {
        case NSAlertFirstButtonReturn:  reply(CDRQuitDecisionQuitAndUpdate); break;
        case NSAlertSecondButtonReturn: reply(CDRQuitDecisionUpdateOnQuit); break;
        default:                        reply(CDRQuitDecisionSkip); break;
    }
}

- (void)presentDeferredOfferForAppNamed:(NSString *)appName
                                version:(NSString *)version
                          deferredUntil:(NSDate *)deferredUntil
                             completion:(void (^)(BOOL installAnyway))completion {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ %@ is available", appName, version];
    alert.informativeText = CDRDeferredOfferCopy(appName, version, deferredUntil);
    [alert addButtonWithTitle:@"Install Anyway"];
    [alert addButtonWithTitle:@"Not Now"];
    completion([alert runModal] == NSAlertFirstButtonReturn);
}

- (void)presentRetractionNotice:(NSString *)message vendorURL:(NSURL *)vendorURL {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Update retracted";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    if (vendorURL) [alert addButtonWithTitle:@"Developer's Site"];
    if ([alert runModal] == NSAlertSecondButtonReturn && vendorURL) {
        [[NSWorkspace sharedWorkspace] openURL:vendorURL];
    }
}

- (void)presentRelaunchOfferForAppNamed:(NSString *)appName appURL:(NSURL *)appURL {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Update installed";
    alert.informativeText = [NSString stringWithFormat:@"Relaunch %@ now?", appName];
    [alert addButtonWithTitle:@"Relaunch"];
    [alert addButtonWithTitle:@"Not Now"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL
                                              configuration:config
                                          completionHandler:nil];
    }
}

#pragma mark - CDRUpdatePresenting (passive group — never modal)

- (void)notifyUpdateAvailableForAppNamed:(NSString *)appName
                                bundleID:(NSString *)bundleID
                                 version:(NSString *)version
                                 urgency:(CDRUrgency)urgency {
    [self.notificationPresenter postUpdateAvailableForAppNamed:appName
                                                      bundleID:bundleID
                                                       version:version
                                                       urgency:urgency];
}

- (void)notifyRetractedPending:(NSString *)message
                      bundleID:(NSString *)bundleID
                     vendorURL:(NSURL *)vendorURL {
    [self.notificationPresenter postNoticeWithTitle:@"Update retracted"
                                               body:message
                                           bundleID:bundleID
                                            version:nil
                                           category:CDRNotificationCategoryRetracted
                                          vendorURL:vendorURL];
}

- (void)notifyRetractedInstalled:(NSString *)message
                        bundleID:(NSString *)bundleID
                       vendorURL:(NSURL *)vendorURL {
    [self.notificationPresenter postNoticeWithTitle:@"Update recalled"
                                               body:message
                                           bundleID:bundleID
                                            version:nil
                                           category:CDRNotificationCategoryRetracted
                                          vendorURL:vendorURL];
}

- (void)notifyInstallCompletedForAppNamed:(NSString *)appName
                                 bundleID:(NSString *)bundleID
                                  version:(NSString *)version {
    NSString *body = version
        ? [NSString stringWithFormat:@"%@ is now version %@.", appName, version]
        : [NSString stringWithFormat:@"%@ was updated.", appName];
    [self.notificationPresenter postNoticeWithTitle:@"Update installed"
                                               body:body
                                           bundleID:bundleID
                                            version:version
                                           category:CDRNotificationCategoryInstalled
                                          vendorURL:nil];
}

- (void)notifyInstallFailedForAppNamed:(NSString *)appName
                              bundleID:(NSString *)bundleID
                                 error:(NSError *)error
                             vendorURL:(NSURL *)vendorURL {
    NSString *body = vendorURL
        ? [NSString stringWithFormat:@"%@ You can update manually from the developer's site.",
           error.localizedDescription]
        : error.localizedDescription;
    [self.notificationPresenter postNoticeWithTitle:
        [NSString stringWithFormat:@"Could not update %@", appName]
                                               body:body
                                           bundleID:bundleID
                                            version:nil
                                           category:(vendorURL ? CDRNotificationCategoryRetracted
                                                               : CDRNotificationCategoryInstalled)
                                          vendorURL:vendorURL];
}

#pragma mark - NSApplicationDelegate

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    // A resident updater outlives its window; the menu bar item, Dock icon,
    // or reopen (Dock click) get back to it.
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) [self showStatusWindow];
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    // Never interrupt a swap mid-flight; parked waits die with the process
    // (staging is cleaned next launch — the swap never happened).
    if (self.updateController.hasOperationsInCriticalPhase) {
        self.terminationPending = YES;
        [CDRSharedLog log:@"Quit requested — finishing the update in progress first."];
        return NSTerminateLater;
    }
    return NSTerminateNow;
}

@end
