//
//  CDRUpdateOperation.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class CDRAppRegistration;
@class CDRManifest;
@class CDRDevModeSession;
@class CDRUpdateOperation;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CDRUpdatePhase) {
    CDRUpdatePhaseIdle = 0,
    CDRUpdatePhaseFetching,
    CDRUpdatePhaseDownloading,
    CDRUpdatePhaseExtracting,
    CDRUpdatePhaseVerifying,
    CDRUpdatePhaseAwaitingQuit,
    CDRUpdatePhaseSwapping,
    CDRUpdatePhaseFinishing,
    CDRUpdatePhaseDone,
    CDRUpdatePhaseFailed,
};

NSString *CDRUpdatePhaseName(CDRUpdatePhase phase);

/// The user's answer to "the app is running" (replace-flow.md §4).
typedef NS_ENUM(NSInteger, CDRQuitDecision) {
    /// Politely terminate now (30s grace), then swap.
    CDRQuitDecisionQuitAndUpdate = 0,
    /// Park: observe termination (no terminate, no timeout), then swap.
    CDRQuitDecisionUpdateOnQuit,
    /// Abort cleanly (CDRErrorUserDeclinedQuit).
    CDRQuitDecisionSkip,
};

@protocol CDRUpdateOperationDelegate <NSObject>
- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase;
/// The managed app is running; the user decides (never force-terminate).
/// Called on the main queue.
- (void)updateOperation:(CDRUpdateOperation *)op
    requestsQuitDecisionFor:(NSArray<NSRunningApplication *> *)runningApps
                      reply:(void (^)(CDRQuitDecision decision))reply;
/// Terminal callback, main queue. error nil = success. wasRunning reports
/// whether the app was quit by the flow (offer relaunch).
- (void)updateOperation:(CDRUpdateOperation *)op
     didFinishWithError:(nullable NSError *)error
      appWasQuitByFlow:(BOOL)wasQuit;
@optional
- (void)updateOperation:(CDRUpdateOperation *)op logMessage:(NSString *)message;
@end

/// The orchestrator (replace-flow.md §§0–7): verify → stage → quit → swap →
/// dequarantine → finish, with the invariant that any failure at any step
/// leaves /Applications exactly as it was. All work off the main queue except
/// delegate callbacks.
///
/// Order of operations enforced here:
///   1. Capture installed identity (bundle ID, versions, TEAM ID — the anchor).
///      An unsigned or ad-hoc installed app fails HERE, before any download.
///   2. Last-moment manifest re-fetch (retraction.md): the manifest passed in
///      may be hours old; fetch fresh and refuse if the advertised version
///      regressed below what the caller was shown.
///   3. Download to staging (same volume) — sha256 checked if the manifest has it.
///   4. Extract (zip/DMG by content).
///   5. Verify the STAGED bundle: bundle-ID match → strictly-newer version
///      (from the staged Info.plist, never the manifest) → pinned Team ID
///      signature validation → notarization assessment.
///   6. Dequarantine the staged bundle (pre-swap: the swap stays the sole
///      mutation of /Applications).
///   7. Quit check (delegate decision; polite terminate only).
///   8. Atomic swap; displaced bundle to Trash (non-fatal if that fails).
///   9. Clean staging.
@interface CDRUpdateOperation : NSObject

- (instancetype)initWithRegistration:(CDRAppRegistration *)registration
                            manifest:(CDRManifest *)manifest
                             session:(CDRDevModeSession *)session
                            delegate:(id<CDRUpdateOperationDelegate>)delegate;

@property (nonatomic, readonly) CDRUpdatePhase phase;
@property (nonatomic, readonly) CDRAppRegistration *registration;

/// YES while parked in AwaitingQuit after an UpdateOnQuit decision.
@property (atomic, readonly, getter=isParkedAwaitingQuit) BOOL parkedAwaitingQuit;

/// Starts the operation. One shot; create a new operation per attempt.
- (void)start;

/// Cancels a parked update-on-quit: stops observing, cleans staging, finishes
/// with CDRErrorUpdateCancelled. Honored only while parked in AwaitingQuit —
/// a no-op in every other phase (a swap is never interrupted). Best-effort:
/// if the app quits at the same moment, whichever lands first wins.
- (void)cancelParkedUpdate;

@end

NS_ASSUME_NONNULL_END
