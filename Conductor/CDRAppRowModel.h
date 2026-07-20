//
//  CDRAppRowModel.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRUpdateOperation.h"

@class CDRAppRegistration;
@class CDRUpdateDecision;
@class CDRManifest;

NS_ASSUME_NONNULL_BEGIN

/// The presentation state of one managed app. Both UI surfaces (status window,
/// menu bar) render exclusively from this model so they cannot drift.
typedef NS_ENUM(NSInteger, CDRAppRowState) {
    /// Not yet checked this launch.
    CDRAppRowStateUnknown = 0,
    /// Also DroppedSilently — the two present identically by design
    /// (retraction.md: no promise was made, no correction is owed).
    CDRAppRowStateUpToDate,
    CDRAppRowStateAvailable,
    /// Soaking (spec term) — user-facing text says "deferred", never "soak".
    CDRAppRowStateDeferred,
    /// Retraction State B: the recalled build is installed. Persistent.
    CDRAppRowStateRecalled,
    /// The last check failed; the vendor URL is the escape hatch.
    CDRAppRowStateCheckFailed,
    CDRAppRowStateIgnored,
    /// An update operation is running; stateLine carries the phase name.
    CDRAppRowStateWorking,
    /// Parked update-on-quit: verified and staged, waiting for termination.
    CDRAppRowStateWaitingForQuit,
};

typedef NS_OPTIONS(NSUInteger, CDRAppRowActions) {
    CDRAppRowActionNone          = 0,
    CDRAppRowActionInstall       = 1 << 0,
    /// Per-app deliberate check — the act that breaks through a deferral
    /// (deferral.md). Available even on ignored rows: user intent overrides.
    CDRAppRowActionCheckNow      = 1 << 1,
    CDRAppRowActionIgnore        = 1 << 2,
    CDRAppRowActionUnignore      = 1 << 3,
    CDRAppRowActionVendorSite    = 1 << 4,
    /// Cancel a parked update-on-quit.
    CDRAppRowActionCancelPending = 1 << 5,
};

@interface CDRAppRowModel : NSObject

@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly) NSString *appName;
/// "1.0" or "1.0 (100)" for the Installed column.
@property (nonatomic, readonly) NSString *installedVersionDisplay;
@property (nonatomic, readonly) CDRAppRowState state;
/// Short human state text, e.g. "1.1 available (installed: 1.0)",
/// "deferred until Jul 27, 2026", "recalled — see developer's site".
@property (nonatomic, readonly) NSString *stateLine;
@property (nonatomic, readonly) CDRAppRowActions actions;
/// Whether this row should light the attention badge: an actionable Available
/// update, or a retraction State A notice. State B never badges — its only
/// action is external (the vendor's site); it keeps a persistent row line
/// instead (roadmap M2 decision).
@property (nonatomic, readonly) BOOL contributesToBadge;
@property (nonatomic, readonly, nullable) NSURL *vendorURL;
/// The manifest version behind an Available row (nil otherwise).
@property (nonatomic, readonly, nullable) NSString *availableVersion;

/// Pure mapping — no I/O, no clock. Precedence: parked > working > ignored >
/// lastError > decision > unknown.
+ (instancetype)modelForRegistration:(CDRAppRegistration *)registration
                        lastDecision:(nullable CDRUpdateDecision *)decision
                     decidedManifest:(nullable CDRManifest *)manifest
                           lastError:(nullable NSError *)error
                             ignored:(BOOL)ignored
                      operationPhase:(CDRUpdatePhase)operationPhase
                              parked:(BOOL)parked;

@end

NS_ASSUME_NONNULL_END
