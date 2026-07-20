//
//  CDRQuitMonitor.m
//  Conductor
//

#import "CDRQuitMonitor.h"

@interface CDRQuitMonitor ()
@property (nonatomic, nullable) id observerToken;
@property (nonatomic, copy, nullable) void (^observeCompletion)(void);
@end

@implementation CDRQuitMonitor

+ (NSArray<NSRunningApplication *> *)runningInstancesOfBundleID:(NSString *)bundleID {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
}

- (void)requestQuitOfBundleID:(NSString *)bundleID
                      timeout:(NSTimeInterval)timeout
                   completion:(void (^)(BOOL))completion {
    NSArray<NSRunningApplication *> *running = [CDRQuitMonitor runningInstancesOfBundleID:bundleID];
    if (running.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
        return;
    }

    __block BOOL finished = NO;
    void (^finish)(BOOL) = ^(BOOL ok) {
        if (finished) return;
        finished = YES;
        if (self.observerToken) {
            [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self.observerToken];
            self.observerToken = nil;
        }
        completion(ok);
    };

    self.observerToken = [[NSWorkspace sharedWorkspace].notificationCenter
        addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (![app.bundleIdentifier isEqualToString:bundleID]) return;
        if ([CDRQuitMonitor runningInstancesOfBundleID:bundleID].count == 0) {
            finish(YES);
        }
    }];

    for (NSRunningApplication *app in running) {
        [app terminate]; // polite; the app may prompt to save, the user may cancel
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        finish([CDRQuitMonitor runningInstancesOfBundleID:bundleID].count == 0);
    });
}

- (void)observeTerminationOfBundleID:(NSString *)bundleID
                          completion:(void (^)(void))completion {
    self.observeCompletion = completion;

    __weak typeof(self) weakSelf = self;
    void (^fireIfGone)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.observeCompletion) return;
        if ([CDRQuitMonitor runningInstancesOfBundleID:bundleID].count > 0) return;
        void (^stored)(void) = self.observeCompletion;
        [self cancelObservation];
        stored();
    };

    self.observerToken = [[NSWorkspace sharedWorkspace].notificationCenter
        addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (![app.bundleIdentifier isEqualToString:bundleID]) return;
        fireIfGone();
    }];

    // Zero-running fast path (and a recount in case the app quit between the
    // caller's check and the observer registration).
    dispatch_async(dispatch_get_main_queue(), fireIfGone);
}

- (void)cancelObservation {
    self.observeCompletion = nil;
    if (self.observerToken) {
        [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self.observerToken];
        self.observerToken = nil;
    }
}

@end
