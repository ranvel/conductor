//
//  CDRAppRowModel.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRUpdateOperation.h"
#import "CDRManifest.h"

@class CDRAppRegistration;
@class CDRUpdateDecision;

NS_ASSUME_NONNULL_BEGIN

/// The presentation state of one managed app. Every UI surface (main window,
/// menu bar, Settings) renders exclusively from this model so they cannot drift.
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
    /// Retraction State A: a version the user was told about was withdrawn
    /// and is not installed. Nothing is installable.
    CDRAppRowStateRetracted,

    // The states below are drawn by the main window now; the inputs that
    // produce them arrive with CND-5 (Held, StoppedAtMajor) and CND-7
    // (Inspecting, NeedsNetworkApproval).

    /// The update contains a note type the user installs by hand.
    CDRAppRowStateHeld,
    /// The advertised version's leading component is greater than the
    /// installed one's, and the user stops at major versions.
    CDRAppRowStateStoppedAtMajor,
    /// Downloading and verifying the new build to compare its entitlements.
    CDRAppRowStateInspecting,
    /// The new build gains internet access and the user approves that first.
    CDRAppRowStateNeedsNetworkApproval,
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
    /// "Got it" on a retraction notice: the row goes back to up to date.
    CDRAppRowActionAcknowledge   = 1 << 6,
};

/// The main window's left-pane sections, top to bottom.
typedef NS_ENUM(NSInteger, CDRAppRowSection) {
    CDRAppRowSectionNeedsYou = 0,
    CDRAppRowSectionUpdates,
    CDRAppRowSectionUpToDate,
    /// Rows Conductor can't vouch for either way: not yet checked, the check
    /// failed, or the user ignores the app. Never labelled "up to date".
    CDRAppRowSectionNotChecked,
};
extern const NSInteger CDRAppRowSectionCount;

/// Pure: every state belongs to exactly one section.
CDRAppRowSection CDRAppRowSectionForState(CDRAppRowState state);
NSString *CDRAppRowSectionTitle(CDRAppRowSection section);

/// How loudly the short state line is drawn.
typedef NS_ENUM(NSInteger, CDRAppRowTone) {
    CDRAppRowToneSecondary = 0,
    CDRAppRowTonePrimary,
    /// Amber: something is waiting on the user.
    CDRAppRowToneAttention,
};

/// Optional inputs the controller gathers outside the pure mapping (signing
/// identity now; resolved preferences and network posture in later tickets).
@interface CDRAppRowContext : NSObject
/// The organization on the installed bundle's signing certificate.
@property (nonatomic, copy, nullable) NSString *developerName;
@end

@interface CDRAppRowModel : NSObject

@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly) NSString *appName;
@property (nonatomic, readonly) NSURL *appURL;
/// "1.0" or "1.0 (100)".
@property (nonatomic, readonly) NSString *installedVersionDisplay;
/// The installed short version alone.
@property (nonatomic, readonly) NSString *installedVersion;
@property (nonatomic, readonly) CDRAppRowState state;
/// Full-sentence state text for the menu bar and the log, e.g.
/// "1.1 available (installed: 1.0)", "recalled — see developer's site".
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

#pragma mark Main window

@property (nonatomic, readonly) CDRAppRowSection section;
/// The manifest's version whenever it is newer than the installed one —
/// including deferred, held and in-progress rows. Nil otherwise.
@property (nonatomic, readonly, nullable) NSString *advertisedVersion;
/// "1.2 → 1.4", or just "1.1" when there is nothing newer to show.
@property (nonatomic, readonly) NSString *versionPairDisplay;
/// SF Symbol name for the glyph that leads the short state line.
@property (nonatomic, readonly) NSString *stateSymbolName;
@property (nonatomic, readonly) CDRAppRowTone stateTone;
/// The left-pane state line: "Update available", "Held · includes a
/// removal", "Deferred · 2 days left". Takes the clock as an argument so the
/// mapping itself stays pure.
- (NSString *)shortStateLineAsOf:(NSDate *)now;

/// What the update contains: the advertised release, then any skipped
/// intermediate versions, newest first (CDRManifest -releasesNewerThanVersion:).
/// Empty when there is no newer version.
@property (nonatomic, readonly) NSArray<CDRRelease *> *releases;
/// The category dots: the types present in the advertised release's notes,
/// or Retracted alone for a retraction notice.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet noteTypes;
/// Skipped intermediate versions ("Includes 1.3"), newest first.
@property (nonatomic, readonly) NSArray<NSString *> *includedVersions;
@property (nonatomic, readonly, nullable) NSDate *releaseDate;
@property (nonatomic, readonly, nullable) NSNumber *artifactSize;
@property (nonatomic, readonly, nullable) NSURL *changelogURL;
@property (nonatomic, readonly) CDRUrgency urgency;

@property (nonatomic, readonly, nullable) NSDate *deferredUntil;
/// The withdrawn version (Retracted) or the recalled one (Recalled).
@property (nonatomic, readonly, nullable) NSString *retractedVersion;
/// The note types that put this row in Held, in the fixed order.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet heldTypes;
@property (nonatomic, readonly) CDRUpdatePhase operationPhase;
@property (nonatomic, readonly, nullable) NSString *errorDescription;
@property (nonatomic, readonly, nullable) NSString *developerName;

/// Pure mapping — no I/O, no clock. Precedence: parked > working > ignored >
/// lastError > decision > unknown.
+ (instancetype)modelForRegistration:(CDRAppRegistration *)registration
                        lastDecision:(nullable CDRUpdateDecision *)decision
                     decidedManifest:(nullable CDRManifest *)manifest
                           lastError:(nullable NSError *)error
                             ignored:(BOOL)ignored
                      operationPhase:(CDRUpdatePhase)operationPhase
                              parked:(BOOL)parked
                             context:(nullable CDRAppRowContext *)context;

/// As above with no context.
+ (instancetype)modelForRegistration:(CDRAppRegistration *)registration
                        lastDecision:(nullable CDRUpdateDecision *)decision
                     decidedManifest:(nullable CDRManifest *)manifest
                           lastError:(nullable NSError *)error
                             ignored:(BOOL)ignored
                      operationPhase:(CDRUpdatePhase)operationPhase
                              parked:(BOOL)parked;

@end

NS_ASSUME_NONNULL_END
