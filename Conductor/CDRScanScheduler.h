//
//  CDRScanScheduler.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How often passive background checks run. One global value; per-app cadence
/// is deliberately deferred (roadmap).
typedef NS_ENUM(NSInteger, CDRScanCadence) {
    CDRScanCadenceManual = 0,
    CDRScanCadenceSixHours,
    CDRScanCadenceDaily,
    CDRScanCadenceWeekly,
};

/// NSUserDefaults token round-trip ("manual" / "6h" / "1d" / "1w");
/// garbage → Daily (the default).
CDRScanCadence CDRScanCadenceFromDefaultsToken(NSString *_Nullable token);
NSString *CDRScanCadenceDefaultsToken(CDRScanCadence cadence);
NSTimeInterval CDRScanCadenceInterval(CDRScanCadence cadence); // 0 for Manual

/// The key and token format are the durable contract (like CDRSoakDuration).
extern NSString * const CDRScanCadenceDefaultsKey;
extern NSString * const CDRLastScanDateDefaultsKey;
/// Debug-only: a positive number of seconds overrides the cadence interval so
/// scheduler behavior can be verified without waiting hours.
extern NSString * const CDRScanIntervalOverrideDefaultsKey;

typedef NS_ENUM(NSInteger, CDRScanTrigger) {
    CDRScanTriggerTimer = 0,
    CDRScanTriggerWake,
    CDRScanTriggerNetworkChange,
};

NSString *CDRScanTriggerName(CDRScanTrigger trigger);

/// Scheduled background scans: a repeating timer plus wake and
/// network-becomes-reachable triggers, all funneled through one pure decision
/// (`shouldScanForTrigger:now:`) so coalescing is unit-testable:
///
/// - Manual cadence: never.
/// - Any trigger within the minimum spacing of the last scan: no (wake +
///   network-change often fire together; relaunch must not stampede — the
///   last-scan date is persisted).
/// - Wake/network additionally require a full cadence interval to have
///   elapsed: they exist to catch up a missed scan, not to add extra ones.
///
/// The owner decides when a scan actually happened (`noteScanCompletedAt:`).
/// Not started at all under dev mode — dev sessions are manual by design.
@interface CDRScanScheduler : NSObject

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                         handler:(void (^)(CDRScanTrigger trigger))handler;

/// Re-arms the timer when changed while started.
@property (nonatomic) CDRScanCadence cadence;
/// Persisted under CDRLastScanDateDefaultsKey.
@property (nonatomic, readonly, nullable) NSDate *lastScanDate;

- (void)start;
- (void)stop;

/// The pure decision core; the trigger plumbing calls exactly this.
- (BOOL)shouldScanForTrigger:(CDRScanTrigger)trigger now:(NSDate *)now;
- (void)noteScanCompletedAt:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
