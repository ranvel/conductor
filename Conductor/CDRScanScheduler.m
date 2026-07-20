//
//  CDRScanScheduler.m
//  Conductor
//

#import "CDRScanScheduler.h"
#import <AppKit/AppKit.h>
#import <Network/Network.h>

NSString * const CDRScanCadenceDefaultsKey = @"CDRScanCadence";
NSString * const CDRLastScanDateDefaultsKey = @"CDRLastScanDate";
NSString * const CDRScanIntervalOverrideDefaultsKey = @"CDRScanIntervalOverrideSeconds";

static const NSTimeInterval kHour = 60.0 * 60.0;
static const NSTimeInterval kMinimumSpacing = 15.0 * 60.0;

CDRScanCadence CDRScanCadenceFromDefaultsToken(NSString *token) {
    if ([token isEqualToString:@"manual"]) return CDRScanCadenceManual;
    if ([token isEqualToString:@"6h"]) return CDRScanCadenceSixHours;
    if ([token isEqualToString:@"1w"]) return CDRScanCadenceWeekly;
    return CDRScanCadenceDaily;
}

NSString *CDRScanCadenceDefaultsToken(CDRScanCadence cadence) {
    switch (cadence) {
        case CDRScanCadenceManual:   return @"manual";
        case CDRScanCadenceSixHours: return @"6h";
        case CDRScanCadenceDaily:    return @"1d";
        case CDRScanCadenceWeekly:   return @"1w";
    }
    return @"1d";
}

NSTimeInterval CDRScanCadenceInterval(CDRScanCadence cadence) {
    switch (cadence) {
        case CDRScanCadenceManual:   return 0;
        case CDRScanCadenceSixHours: return 6 * kHour;
        case CDRScanCadenceDaily:    return 24 * kHour;
        case CDRScanCadenceWeekly:   return 7 * 24 * kHour;
    }
    return 24 * kHour;
}

NSString *CDRScanTriggerName(CDRScanTrigger trigger) {
    switch (trigger) {
        case CDRScanTriggerTimer:         return @"scheduled";
        case CDRScanTriggerWake:          return @"wake";
        case CDRScanTriggerNetworkChange: return @"network change";
    }
    return @"scheduled";
}

@interface CDRScanScheduler ()
@property (nonatomic) NSUserDefaults *defaults;
@property (nonatomic, copy) void (^handler)(CDRScanTrigger trigger);
@property (nonatomic, nullable) NSTimer *timer;
@property (nonatomic, nullable) id wakeObserver;
@property (nonatomic, nullable) nw_path_monitor_t pathMonitor;
@property (nonatomic) BOOL pathWasSatisfied;
@property (nonatomic) BOOL started;
@end

@implementation CDRScanScheduler

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                         handler:(void (^)(CDRScanTrigger))handler {
    self = [super init];
    if (!self) return nil;
    _defaults = defaults;
    _handler = [handler copy];
    _cadence = CDRScanCadenceDaily;
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Decision core (pure)

- (NSTimeInterval)effectiveInterval {
    double override = [self.defaults doubleForKey:CDRScanIntervalOverrideDefaultsKey];
    if (override > 0) return override;
    return CDRScanCadenceInterval(self.cadence);
}

- (BOOL)shouldScanForTrigger:(CDRScanTrigger)trigger now:(NSDate *)now {
    if (self.cadence == CDRScanCadenceManual) return NO;

    NSDate *last = self.lastScanDate;
    if (!last) return YES; // never scanned: any trigger may run the first one

    NSTimeInterval interval = [self effectiveInterval];
    NSTimeInterval sinceLast = [now timeIntervalSinceDate:last];
    // The spacing floor shrinks with a debug override so short intervals stay
    // observable.
    NSTimeInterval spacing = MIN(kMinimumSpacing, interval / 2.0);
    if (sinceLast < spacing) return NO;
    // Wake/network catch up a missed scan; they never add extra ones.
    if (trigger != CDRScanTriggerTimer && sinceLast < interval) return NO;
    return YES;
}

- (nullable NSDate *)lastScanDate {
    id stored = [self.defaults objectForKey:CDRLastScanDateDefaultsKey];
    return [stored isKindOfClass:[NSDate class]] ? stored : nil;
}

- (void)noteScanCompletedAt:(NSDate *)date {
    [self.defaults setObject:date forKey:CDRLastScanDateDefaultsKey];
}

#pragma mark - Plumbing

- (void)setCadence:(CDRScanCadence)cadence {
    _cadence = cadence;
    if (self.started) {
        [self stop];
        [self start];
    }
}

- (void)attemptScanForTrigger:(CDRScanTrigger)trigger {
    if (![self shouldScanForTrigger:trigger now:[NSDate date]]) return;
    self.handler(trigger);
}

- (void)start {
    if (self.started) return;
    self.started = YES;

    NSTimeInterval interval = [self effectiveInterval];
    if (interval > 0) {
        __weak typeof(self) weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:interval repeats:YES block:^(NSTimer *t) {
            [weakSelf attemptScanForTrigger:CDRScanTriggerTimer];
        }];
        self.timer.tolerance = interval * 0.1;
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }

    __weak typeof(self) weakSelf = self;
    self.wakeObserver = [[NSWorkspace sharedWorkspace].notificationCenter
        addObserverForName:NSWorkspaceDidWakeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [weakSelf attemptScanForTrigger:CDRScanTriggerWake];
    }];

    self.pathWasSatisfied = YES; // assume online at start; only transitions count
    self.pathMonitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(self.pathMonitor, dispatch_get_main_queue());
    nw_path_monitor_set_update_handler(self.pathMonitor, ^(nw_path_t path) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        BOOL satisfied = (nw_path_get_status(path) == nw_path_status_satisfied);
        BOOL cameOnline = satisfied && !self.pathWasSatisfied;
        self.pathWasSatisfied = satisfied;
        if (cameOnline) [self attemptScanForTrigger:CDRScanTriggerNetworkChange];
    });
    nw_path_monitor_start(self.pathMonitor);
}

- (void)stop {
    self.started = NO;
    [self.timer invalidate];
    self.timer = nil;
    if (self.wakeObserver) {
        [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self.wakeObserver];
        self.wakeObserver = nil;
    }
    if (self.pathMonitor) {
        nw_path_monitor_cancel(self.pathMonitor);
        self.pathMonitor = nil;
    }
}

@end
