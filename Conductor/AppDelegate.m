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
#import "CDRUpdatePolicy.h"
#import "CDRUpdateStateStore.h"

@interface AppDelegate () <CDRUpdateOperationDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) CDRAppScanner *scanner;
@property (nonatomic) CDRManifestFetcher *fetcher;
@property (nonatomic) CDRUpdateStateStore *stateStore;
@property (nonatomic) CDRStatusWindowController *statusWindowController;
@property (nonatomic) NSMutableDictionary<NSString *, CDRManifest *> *knownManifests; // bundleID → last fetched
@property (nonatomic, nullable) CDRUpdateOperation *activeOperation;
/// Whether the active operation reached the download phase. Distinguishes the
/// two CDRErrorDowngradeRefused sources: the pre-download last-moment re-check
/// (a retraction — State A) vs the staged-bundle version gate (a replayed
/// older artifact — a plain refusal, no retraction messaging).
@property (nonatomic) BOOL activeOperationReachedDownload;
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
    self.stateStore = [CDRUpdateStateStore defaultStore];
    self.knownManifests = [NSMutableDictionary dictionary];
    self.statusWindowController = [[CDRStatusWindowController alloc] initWithSession:self.session];

    __weak typeof(self) weakSelf = self;
    self.statusWindowController.onCheck = ^(CDRAppRegistration *reg) {
        // Check Now on a specific app is the deliberate act that breaks
        // through a soak (deferral.md) — per-app, per-invocation.
        [weakSelf checkForUpdate:reg breakThrough:YES];
    };
    self.statusWindowController.onCheckAll = ^{
        for (CDRAppRegistration *reg in weakSelf.statusWindowController.registrations) {
            [weakSelf checkForUpdate:reg breakThrough:NO];
        }
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

- (void)checkForUpdate:(CDRAppRegistration *)reg breakThrough:(BOOL)breakThrough {
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

        // The fetcher completes on an arbitrary queue; decide and present on
        // main (state mutations, alerts).
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDate *now = [NSDate date];
            CDRSoakDuration soak = CDRSoakDurationFromDefaultsToken(
                [[NSUserDefaults standardUserDefaults] stringForKey:CDRSoakDurationDefaultsKey]);
            CDRUpdateDecision *decision = [CDRUpdatePolicy decisionForRegistration:reg
                                                                          manifest:manifest
                                                                             state:[self.stateStore stateForBundleID:reg.bundleID]
                                                                      soakDuration:soak
                                                                      breakThrough:breakThrough
                                                                               now:now];
            [self.stateStore putState:decision.stateAfterCheck];
            [self presentDecision:decision manifest:manifest registration:reg];
        });
    }];
}

- (void)presentDecision:(CDRUpdateDecision *)decision
               manifest:(CDRManifest *)manifest
           registration:(CDRAppRegistration *)reg {
    NSString *bundleID = reg.bundleID;
    NSString *appName = reg.appURL.lastPathComponent.stringByDeletingPathExtension;

    switch (decision.outcome) {
        case CDRUpdateOutcomeAvailable: {
            self.knownManifests[bundleID] = manifest;
            [self.statusWindowController setRowStatus:manifest.version installEnabled:YES forBundleID:bundleID];
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: update %@ available (installed: %@).",
                 bundleID, manifest.version, reg.installedShortVersion]];
            if (decision.urgency != CDRUrgencyNone) {
                [self.statusWindowController appendLog:
                    [NSString stringWithFormat:@"%@: %@", bundleID,
                     CDRUrgencyNoticeCopy(decision.urgency, appName, manifest.version)]];
            }
            break;
        }

        case CDRUpdateOutcomeDeferred: {
            // Hidden while soaking: Install must not be reachable.
            [self.knownManifests removeObjectForKey:bundleID];
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateStyle = NSDateFormatterMediumStyle;
            fmt.timeStyle = NSDateFormatterNoStyle;
            [self.statusWindowController setRowStatus:
                [NSString stringWithFormat:@"deferred until %@", [fmt stringFromDate:decision.deferredUntil]]
                                       installEnabled:NO forBundleID:bundleID];
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: %@ is deferred until %@ by the update settings.",
                 bundleID, manifest.version, [fmt stringFromDate:decision.deferredUntil]]];
            break;
        }

        case CDRUpdateOutcomeDeferredOffered: {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"%@ %@ is available", appName, manifest.version];
            alert.informativeText = CDRDeferredOfferCopy(appName, manifest.version, decision.deferredUntil);
            [alert addButtonWithTitle:@"Install Anyway"];
            [alert addButtonWithTitle:@"Not Now"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                // Consent marks it notified — retraction loudness now applies
                // to this version like any surfaced update (deferral.md).
                [self.stateStore noteNotifiedVersion:manifest.version build:manifest.build
                                         forBundleID:bundleID at:[NSDate date]];
                self.knownManifests[bundleID] = manifest;
                [self.statusWindowController setRowStatus:manifest.version installEnabled:YES forBundleID:bundleID];
                [self installUpdate:reg];
            } else {
                [self.knownManifests removeObjectForKey:bundleID];
                [self.statusWindowController setRowStatus:@"deferred" installEnabled:NO forBundleID:bundleID];
            }
            break;
        }

        case CDRUpdateOutcomeRetractedPending: {
            // Retraction State A. Loudness during a check is the visible row
            // state + log, never a modal — modals are reserved for the moment
            // the user tries to apply a retracted update (the last-moment
            // re-check path in the operation delegate below).
            [self.knownManifests removeObjectForKey:bundleID];
            [self.statusWindowController setRowStatus:@"update retracted" installEnabled:NO forBundleID:bundleID];
            NSString *message = CDRRetractedPendingCopy(appName, decision.retractedVersion, reg.installedShortVersion);
            [self.statusWindowController appendLog:[NSString stringWithFormat:@"%@: %@", bundleID, message]];
            break;
        }

        case CDRUpdateOutcomeRetractedInstalled: {
            // Retraction State B: inform, never auto-downgrade. Passive row
            // status persists; no modal on a check.
            [self.knownManifests removeObjectForKey:bundleID];
            [self.statusWindowController setRowStatus:@"recalled — see developer's site"
                                       installEnabled:NO forBundleID:bundleID];
            NSString *message = CDRRetractedInstalledCopy(appName, decision.retractedVersion);
            [self.statusWindowController appendLog:[NSString stringWithFormat:@"%@: %@", bundleID, message]];
            break;
        }

        case CDRUpdateOutcomeUpToDate:
        case CDRUpdateOutcomeDroppedSilently: {
            // Identical presentation by design: a never-surfaced version that
            // vanished owes the user nothing (retraction.md).
            [self.knownManifests removeObjectForKey:bundleID];
            [self.statusWindowController setRowStatus:nil installEnabled:NO forBundleID:bundleID];
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: up to date (%@).", bundleID, reg.installedShortVersion]];
            break;
        }
    }
}

/// Modal notice with an optional link out to the vendor/changelog page.
- (void)presentNotice:(NSString *)message linkURL:(nullable NSURL *)url {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Update retracted";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    if (url) [alert addButtonWithTitle:@"Developer's Site"];
    if ([alert runModal] == NSAlertSecondButtonReturn && url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
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
    self.activeOperationReachedDownload = NO;
    [self.activeOperation start];
}

#pragma mark - CDRUpdateOperationDelegate

- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase {
    if (phase == CDRUpdatePhaseDownloading) self.activeOperationReachedDownload = YES;
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
        if ([error.domain isEqualToString:CDRErrorDomain] && error.code == CDRErrorDowngradeRefused
            && !self.activeOperationReachedDownload) {
            // The operation's last-moment manifest re-check caught a
            // retraction between notify and install (retraction.md) — this is
            // State A, not a generic failure. The operation stays state-free;
            // the state reaction lives here.
            [self.stateStore clearNotifiedVersionForBundleID:bundleID at:[NSDate date]];
            [self.knownManifests removeObjectForKey:bundleID];
            [self.statusWindowController setRowStatus:nil installEnabled:NO forBundleID:bundleID];
            [self.statusWindowController appendLog:
                [NSString stringWithFormat:@"%@: %@", bundleID, error.localizedDescription]];
            [self presentNotice:error.localizedDescription
                        linkURL:(error.userInfo[CDRErrorVendorURLKey] ?: op.registration.vendorURL)];
            return;
        }
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
    [self.statusWindowController setRowStatus:nil installEnabled:NO forBundleID:bundleID];
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
