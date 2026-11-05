//
//  CDRUpdateController.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRAppRowModel.h"
#import "CDRUpdatePresenting.h"

@class CDRDevModeSession;
@class CDRAppScanner;
@class CDRManifestFetcher;
@class CDRUpdateStateStore;
@class CDRAppRegistration;
@class CDRUpdateDecision;
@class CDRAppUpdateState;

NS_ASSUME_NONNULL_BEGIN

/// The app-level coordinator: owns discovery, checks, per-app decisions, and
/// update operations (one per bundle ID, several allowed — parked
/// update-on-quit operations coexist). Publishes rowModels for both UI
/// surfaces and routes all presentation through the presenter seam.
/// Main-thread only (matches AppKit); engine callbacks arrive on main.
@interface CDRUpdateController : NSObject

- (instancetype)initWithSession:(CDRDevModeSession *)session
                        scanner:(CDRAppScanner *)scanner
                        fetcher:(CDRManifestFetcher *)fetcher
                     stateStore:(CDRUpdateStateStore *)stateStore
                       defaults:(NSUserDefaults *)defaults;

@property (nonatomic, weak) id<CDRUpdatePresenting> presenter;

/// The visible registrations (already session-filtered), refreshed by -rescan.
@property (nonatomic, readonly, copy) NSArray<CDRAppRegistration *> *registrations;

/// One row per visible registration, rebuilt on every state change.
@property (nonatomic, readonly, copy) NSArray<CDRAppRowModel *> *rowModels;
/// When a manifest was last fetched successfully for any app (nil before the
/// first check this launch). Feeds the window's "Checked 4 min ago".
@property (nonatomic, readonly, nullable) NSDate *lastCheckDate;
@property (nonatomic, copy, nullable) void (^onRowModelsChanged)(void);

/// Aggregate operation progress for a single UI bar: fired on phase
/// transitions and ~2 Hz download ticks, main queue. fraction < 0 means
/// indeterminate (busy, no byte counts); active == NO means nothing is in
/// flight (hide the bar). Deliberately separate from onRowModelsChanged so
/// download ticks never trigger table reloads. Parked update-on-quit waits
/// are not "active" — they can sit for days and their row already says so.
@property (nonatomic, copy, nullable) void (^onProgressChanged)
    (BOOL active, double fraction, NSString *_Nullable detail);

/// Disk discovery + session filter. Cheap, synchronous, no network.
- (void)rescan;
/// A Settings value or a per-app override changed: rebuild the rows from the
/// newly resolved preferences.
- (void)preferencesDidChange;

/// The global check (Check All / scheduler): every non-ignored app,
/// breakThrough:NO — a passive sweep never breaks a deferral.
- (void)checkAllPassive;

/// Per-app check. userInitiated:YES is the deliberate act that breaks through
/// a deferral (deferral.md) and overrides ignore.
- (void)checkApp:(NSString *)bundleID userInitiated:(BOOL)userInitiated;

/// Starts an update operation for a previously checked app (requires a known
/// manifest from the last Available decision).
- (void)installApp:(NSString *)bundleID;

/// Single routing point for row actions from any UI surface.
- (void)performRowAction:(CDRAppRowActions)action forBundleID:(NSString *)bundleID;

/// YES while any operation is past Verifying's point of no return
/// (Downloading … Finishing, excluding a parked wait). Consulted by
/// applicationShouldTerminate:.
- (BOOL)hasOperationsInCriticalPhase;

@end

/// Pure notification-loudness rule, evaluated against the state read BEFORE
/// the decision's stateAfterCheck is persisted: Available warrants a user
/// notification only for a version the user was not already notified about;
/// RetractedPending always (self-limiting — the decision clears its own
/// memory, so it fires once ever); everything else is quiet.
BOOL CDRDecisionWarrantsNotification(CDRUpdateDecision *decision,
                                     CDRAppUpdateState *_Nullable previousState,
                                     CDRManifest *manifest);

NS_ASSUME_NONNULL_END
