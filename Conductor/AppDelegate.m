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
#import "CDRLogWindowController.h"
#import "CDRMenuBarController.h"
#import "CDRNotificationPresenter.h"
#import "CDRScanScheduler.h"
#import "CDRSettingsWindowController.h"
#import "CDRMainWindowController.h"
#import "CDRUpdateController.h"
#import "CDRUpdatePolicy.h"
#import "CDRUpdateStateStore.h"
#import "CDRSharedLog.h"

@interface AppDelegate () <CDRUpdatePresenting>

@property (strong) IBOutlet NSWindow *window;
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) CDRUpdateController *updateController;
@property (nonatomic) CDRMainWindowController *mainWindowController;
@property (nonatomic) CDRMenuBarController *menuBarController;
@property (nonatomic) CDRNotificationPresenter *notificationPresenter;
@property (nonatomic) CDRScanScheduler *scanScheduler;
@property (nonatomic, nullable) CDRSettingsWindowController *settingsWindowController;
@property (nonatomic, nullable) CDRLogWindowController *logWindowController;
/// Set while applicationShouldTerminate: is deferred on in-flight operations.
@property (nonatomic) BOOL terminationPending;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // The template xib's window is unused; the main window is programmatic.
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

    self.mainWindowController = [[CDRMainWindowController alloc] initWithSession:self.session];
    self.menuBarController = [[CDRMenuBarController alloc] initWithSession:self.session];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [self applyDockIconSetting:CDRShowDockIconSetting(defaults)];
    self.menuBarController.preferredVisible = CDRShowMenuBarItemSetting(defaults);

    __weak typeof(self) weakSelf = self;
    void (^onRowAction)(NSString *, CDRAppRowActions) = ^(NSString *bundleID, CDRAppRowActions action) {
        [weakSelf.updateController performRowAction:action forBundleID:bundleID];
    };
    // "Check now" in the window or the menu bar: the same check the
    // scheduler runs, but one the user asked for.
    void (^onCheckAll)(void) = ^{
        [weakSelf.updateController checkAllUserStarted];
    };
    self.updateController.onRowModelsChanged = ^{
        [weakSelf rowModelsChanged];
    };
    self.updateController.onProgressChanged = ^(BOOL active, double fraction, NSString *detail) {
        [weakSelf.mainWindowController setProgressActive:active fraction:fraction detail:detail];
    };
    self.mainWindowController.onRowAction = onRowAction;
    self.mainWindowController.onCheckAll = onCheckAll;
    self.mainWindowController.onScanAgain = ^{
        [weakSelf.updateController rescan];
        [weakSelf.updateController checkAllUserStarted];
    };
    self.mainWindowController.onOpenSettings = ^{
        [weakSelf showSettingsWindow];
    };
    self.mainWindowController.defaults = defaults;
    self.mainWindowController.onPreferencesChanged = ^{
        [weakSelf.updateController preferencesDidChange];
    };
    self.menuBarController.onRowAction = onRowAction;
    self.menuBarController.onCheckAll = onCheckAll;
    self.menuBarController.onOpenWindow = ^{
        [weakSelf showMainWindow];
    };
    self.menuBarController.onOpenSettings = ^{
        [weakSelf showSettingsWindow];
    };
    [self wireAppMenuSettingsItem];
    [self wireWindowMenuItems];

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
            // so the window is the landing surface — on the app in question.
            self.mainWindowController.selectedBundleID = bundleID;
            [self showMainWindow];
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
    [self showMainWindow];

    if (self.session.devModeEnabled) {
        [CDRSharedLog log:
            [NSString stringWithFormat:@"DEV MODE session for %@ — transport check relaxed for this app only; verification unchanged.",
             self.session.devModeBundleID]];
    }
}

- (void)rowModelsChanged {
    NSArray<CDRAppRowModel *> *rows = self.updateController.rowModels;
    self.mainWindowController.rowModels = rows;
    self.mainWindowController.lastCheckDate = self.updateController.lastCheckDate;
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

- (void)showMainWindow {
    [NSApp activateIgnoringOtherApps:YES];
    [self.mainWindowController showWindow:nil];
    [self.mainWindowController.window makeKeyAndOrderFront:nil];
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
        settings.onPreferencesChanged = ^{
            [weakSelf.updateController preferencesDidChange];
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

- (void)showLogWindow {
    if (!self.logWindowController) {
        self.logWindowController = [[CDRLogWindowController alloc] init];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.logWindowController showWindow:nil];
    [self.logWindowController.window makeKeyAndOrderFront:nil];
}

/// Window ▸ Conductor (⌘0) reopens the main window after it is closed;
/// Window ▸ Activity Log (⌘L) opens the log, created lazily on first show.
- (void)wireWindowMenuItems {
    NSMenuItem *main = [[NSMenuItem alloc] initWithTitle:@"Conductor"
                                                  action:@selector(mainWindowMenuItemChosen:)
                                           keyEquivalent:@"0"];
    main.target = self;
    NSMenuItem *log = [[NSMenuItem alloc] initWithTitle:@"Activity Log"
                                                 action:@selector(logMenuItemChosen:)
                                          keyEquivalent:@"l"];
    log.target = self;
    [NSApp.windowsMenu insertItem:main atIndex:0];
    [NSApp.windowsMenu insertItem:log atIndex:1];
    [NSApp.windowsMenu insertItem:[NSMenuItem separatorItem] atIndex:2];
}

- (void)mainWindowMenuItemChosen:(id)sender {
    [self showMainWindow];
}

- (void)logMenuItemChosen:(id)sender {
    [self showLogWindow];
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
    [self.mainWindowController.window makeKeyAndOrderFront:nil];
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

- (void)presentRetractionForAppNamed:(NSString *)appName
                            bundleID:(NSString *)bundleID
                              appURL:(NSURL *)appURL
                    retractedVersion:(NSString *)retractedVersion
                    installedVersion:(NSString *)installedVersion
                             message:(NSString *)message
                           vendorURL:(NSURL *)vendorURL
                          completion:(void (^)(BOOL acknowledged))completion {
    // The sheet only where the user is already looking. Otherwise the same
    // passive notice a background check posts; the row keeps its banner.
    if (!self.mainWindowController.window.isKeyWindow || !self.mainWindowController.canPresentInterruptSheet) {
        [self notifyRetractedPending:message bundleID:bundleID vendorURL:vendorURL];
        completion(NO);
        return;
    }
    self.mainWindowController.selectedBundleID = bundleID;
    CDRInterruptSheetModel *model = [CDRInterruptSheetModel retractionModelForAppNamed:appName
                                                                                appURL:appURL
                                                                      retractedVersion:retractedVersion
                                                                      installedVersion:installedVersion];
    [self.mainWindowController presentInterruptSheet:model completion:^(NSInteger action, BOOL usedLink) {
        completion(YES);
    }];
}

- (void)presentHeldUpdateForAppNamed:(NSString *)appName
                            bundleID:(NSString *)bundleID
                              appURL:(NSURL *)appURL
                             version:(NSString *)version
                          heldGroups:(NSArray<CDRReleaseNoteGroup *> *)heldGroups
                           holdTypes:(CDRReleaseNoteTypeSet)holdTypes
                          completion:(void (^)(BOOL install))completion {
    // The user pressed Install — from the window or the menu bar. Either
    // way the confirmation drops from the window, on that app.
    [self showMainWindow];
    self.mainWindowController.selectedBundleID = bundleID;
    CDRInterruptSheetModel *model = [CDRInterruptSheetModel heldModelForAppNamed:appName
                                                                          appURL:appURL
                                                                         version:version
                                                                      heldGroups:heldGroups
                                                                       holdTypes:holdTypes];
    __weak typeof(self) weakSelf = self;
    [self.mainWindowController presentInterruptSheet:model completion:^(NSInteger action, BOOL usedLink) {
        completion(action == CDRInterruptSheetActionInstall);
        if (usedLink) {
            // "Change in Settings": the hold categories.
            [weakSelf showSettingsWindow];
            [weakSelf.settingsWindowController showSection:CDRSettingsSectionInstallManually];
        }
    }];
}

- (void)presentNetworkApprovalForAppNamed:(NSString *)appName
                                 bundleID:(NSString *)bundleID
                                   appURL:(NSURL *)appURL
                              fromVersion:(NSString *)fromVersion
                                toVersion:(NSString *)toVersion
                                diffLines:(NSArray<CDRInterruptSheetDiffLine *> *)diffLines
                               policyRows:(NSArray<CDRInterruptSheetPolicyRow *> *)policyRows
                               completion:(void (^)(CDRInterruptSheetAction action))completion {
    [self showMainWindow];
    self.mainWindowController.selectedBundleID = bundleID;
    CDRInterruptSheetModel *model = [CDRInterruptSheetModel networkModelForAppNamed:appName
                                                                             appURL:appURL
                                                                        fromVersion:fromVersion
                                                                          toVersion:toVersion
                                                                          diffLines:diffLines
                                                                         policyRows:policyRows];
    [self.mainWindowController presentInterruptSheet:model completion:^(NSInteger action, BOOL usedLink) {
        completion((CDRInterruptSheetAction)action);
    }];
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

- (void)notifyUpdateNeedsAttentionForAppNamed:(NSString *)appName
                                     bundleID:(NSString *)bundleID
                                      version:(NSString *)version
                                       reason:(NSString *)reason {
    // No Install action: tapping lands on the app in the window, where the
    // deliberate click lives.
    [self.notificationPresenter postNoticeWithTitle:
        [NSString stringWithFormat:@"%@ %@ is waiting for you", appName, version]
                                               body:reason
                                           bundleID:bundleID
                                            version:version
                                           category:CDRNotificationCategoryInstalled
                                          vendorURL:nil];
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
    // Nothing about an approval or an inspect-ahead download carries over a
    // quit. By now no operation is mid-swap (applicationShouldTerminate:
    // waits those out), so whatever is left in staging never became an
    // install and is removed. /Applications itself is not touched.
    [self.updateController discardParkedApprovals];
    NSURL *root = [CDRArtifactStager stagingRootNearDestination:
        [NSURL fileURLWithPath:@"/Applications" isDirectory:YES]];
    [[NSFileManager defaultManager] removeItemAtURL:root error:NULL];
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
    if (!flag) [self showMainWindow];
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
