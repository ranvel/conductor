//
//  AppDelegate.m
//  Conductor
//
//  Created by ranvel on 7/19/26.
//

#import "AppDelegate.h"
#import "CDRAppScanner.h"
#import "CDRAppRegistration.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRManifestFetcher.h"
#import "CDRUpdateOperation.h"
#import "CDRVersion.h"
#import "CDRErrors.h"
#import "CDRArtifactStager.h"
#import "CDRStatusWindowController.h"

@interface AppDelegate () <CDRUpdateOperationDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) CDRAppScanner *scanner;
@property (nonatomic) CDRManifestFetcher *fetcher;
@property (nonatomic) CDRStatusWindowController *statusWindowController;
@property (nonatomic) NSMutableDictionary<NSString *, CDRManifest *> *knownManifests; // bundleID → last fetched
@property (nonatomic, nullable) CDRUpdateOperation *activeOperation;
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

    self.scanner = [[CDRAppScanner alloc] init];
    self.fetcher = [[CDRManifestFetcher alloc] initWithSession:self.session];
    self.knownManifests = [NSMutableDictionary dictionary];
    self.statusWindowController = [[CDRStatusWindowController alloc] initWithSession:self.session];

    __weak typeof(self) weakSelf = self;
    self.statusWindowController.onCheck = ^(CDRAppRegistration *reg) {
        [weakSelf checkForUpdate:reg];
    };
    self.statusWindowController.onInstall = ^(CDRAppRegistration *reg) {
        [weakSelf installUpdate:reg];
    };

    [self cleanStaleStaging];
    [self rescan];
    [self.statusWindowController showWindow:nil];
    [self.statusWindowController.window makeKeyAndOrderFront:nil];

    if (self.session.devModeEnabled) {
        [self.statusWindowController appendLog:
            [NSString stringWithFormat:@"DEV MODE session for %@ — transport check relaxed for this app only; verification unchanged.",
             self.session.devModeBundleID]];
    }
}

/// Staging left behind by a crashed or interrupted run is garbage: the swap is
/// atomic, so anything still in .conductor-staging never made it and never will.
- (void)cleanStaleStaging {
    NSURL *root = [CDRArtifactStager stagingRootNearDestination:
        [NSURL fileURLWithPath:@"/Applications" isDirectory:YES]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:root.path]) {
        [[NSFileManager defaultManager] removeItemAtURL:root error:NULL];
        [self.statusWindowController appendLog:@"Removed stale staging from a previous run."];
    }
}

- (void)rescan {
    NSArray<CDRAppRegistration *> *all = [self.scanner scanApplicationsDirectory];
    NSMutableArray<CDRAppRegistration *> *visible = [NSMutableArray array];
    for (CDRAppRegistration *reg in all) {
        if ([self.session isBundleVisible:reg.bundleID]) [visible addObject:reg];
    }
    self.statusWindowController.registrations = visible;
    [self.statusWindowController appendLog:
        [NSString stringWithFormat:@"Scan: %lu managed app(s) found.", (unsigned long)visible.count]];
}

#pragma mark - Check

- (void)checkForUpdate:(CDRAppRegistration *)reg {
    [self.statusWindowController appendLog:
        [NSString stringWithFormat:@"%@: fetching manifest from %@ …", reg.bundleID, reg.updateURL.absoluteString]];

    __weak typeof(self) weakSelf = self;
    [self.fetcher fetchManifestForRegistration:reg completion:^(CDRManifest *manifest, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!manifest) {
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: %@", reg.bundleID, error.localizedDescription]];
            NSURL *vendor = error.userInfo[CDRErrorVendorURLKey];
            if (vendor) {
                [self.statusWindowController appendLog:
                    [NSString stringWithFormat:@"%@: check the developer's site: %@", reg.bundleID, vendor.absoluteString]];
            }
            return;
        }

        BOOL newer = [CDRVersion isVersion:manifest.version build:manifest.build
                                 newerThan:reg.installedShortVersion build:reg.installedBuildVersion];
        if (newer) {
            self.knownManifests[reg.bundleID] = manifest;
            [self.statusWindowController setInstallAvailable:YES forBundleID:reg.bundleID version:manifest.version];
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: update %@ available (installed: %@).",
                 reg.bundleID, manifest.version, reg.installedShortVersion]];
        } else {
            [self.knownManifests removeObjectForKey:reg.bundleID];
            [self.statusWindowController setInstallAvailable:NO forBundleID:reg.bundleID version:nil];
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: up to date (%@).", reg.bundleID, reg.installedShortVersion]];
        }
    }];
}

#pragma mark - Install

- (void)installUpdate:(CDRAppRegistration *)reg {
    if (self.activeOperation) {
        [self.statusWindowController appendLog:@"An update is already in progress."];
        return;
    }
    CDRManifest *manifest = self.knownManifests[reg.bundleID];
    if (!manifest) {
        [self.statusWindowController appendLog:
            [NSString stringWithFormat:@"%@: no known update — run Check first.", reg.bundleID]];
        return;
    }

    self.activeOperation = [[CDRUpdateOperation alloc] initWithRegistration:reg
                                                                   manifest:manifest
                                                                    session:self.session
                                                                   delegate:self];
    [self.activeOperation start];
}

#pragma mark - CDRUpdateOperationDelegate

- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase {
    [self.statusWindowController appendLog:
        [NSString stringWithFormat:@"%@: %@ …", op.registration.bundleID, CDRUpdatePhaseName(phase)]];
}

- (void)updateOperation:(CDRUpdateOperation *)op logMessage:(NSString *)message {
    [self.statusWindowController appendLog:message];
}

- (void)updateOperation:(CDRUpdateOperation *)op
    requestsQuitDecisionFor:(NSArray<NSRunningApplication *> *)runningApps
                      reply:(void (^)(BOOL))reply {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ is running",
                         op.registration.appURL.lastPathComponent.stringByDeletingPathExtension];
    alert.informativeText = @"The app must quit before Conductor can update it. It may ask you to save unsaved work.";
    [alert addButtonWithTitle:@"Quit & Update"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse response = [alert runModal];
    reply(response == NSAlertFirstButtonReturn);
}

- (void)updateOperation:(CDRUpdateOperation *)op
     didFinishWithError:(NSError *)error
       appWasQuitByFlow:(BOOL)wasQuit {
    self.activeOperation = nil;
    NSString *bundleID = op.registration.bundleID;

    if (error) {
        [self.statusWindowController appendLog:
            [NSString stringWithFormat:@"%@: FAILED — %@", bundleID, error.localizedDescription]];
        NSURL *vendor = error.userInfo[CDRErrorVendorURLKey];
        if (vendor) {
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: check the developer's site: %@", bundleID, vendor.absoluteString]];
        }
        return;
    }

    [self.statusWindowController appendLog:
        [NSString stringWithFormat:@"%@: update installed successfully.", bundleID]];
    [self.knownManifests removeObjectForKey:bundleID];
    [self.statusWindowController setInstallAvailable:NO forBundleID:bundleID version:nil];
    [self rescan];

    if (wasQuit) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Update installed";
        alert.informativeText = [NSString stringWithFormat:@"Relaunch %@ now?",
                                 op.registration.appURL.lastPathComponent.stringByDeletingPathExtension];
        [alert addButtonWithTitle:@"Relaunch"];
        [alert addButtonWithTitle:@"Not Now"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
            [[NSWorkspace sharedWorkspace] openApplicationAtURL:op.registration.appURL
                                                  configuration:config
                                              completionHandler:nil];
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end
