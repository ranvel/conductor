//
//  CDRAppRowModel.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRUpdateOperation.h"
#import "CDRManifest.h"

@class CDRAppRegistration;
@class CDRUpdateDecision;
@class CDRUpdatePreferences;
@class CDRRetractionNotice;
@class CDRNetworkInspection;
@class CDRInternetAccessPolicy;
@class CDRInternetAccessPolicyRow;

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


    /// The update contains a note type the user installs by hand.
    CDRAppRowStateHeld,
    /// The advertised version's leading component is greater than the
    /// installed one's, and the user stops at major versions.
    CDRAppRowStateStoppedAtMajor,
    /// Downloading and verifying the new build to compare its entitlements.
    CDRAppRowStateInspecting,
    /// The new build gains internet access and the user approves that first.
    CDRAppRowStateNeedsNetworkApproval,
    /// The user chose "Skip this version" for the advertised version.
    CDRAppRowStateSkipped,
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
    /// "Update now" on a deferred update: the user's consent to surface and
    /// install it before its deferral ends (deferral.md break-through).
    CDRAppRowActionInstallDeferred = 1 << 7,
    /// "Always allow for this app" on a major-version stop: writes a per-app
    /// override so this app no longer stops at major versions.
    CDRAppRowActionAlwaysAllowMajor = 1 << 8,
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
/// The app's effective preferences (Settings with its override applied).
@property (nonatomic, nullable) CDRUpdatePreferences *preferences;
/// A retraction the user hasn't acknowledged. Keeps the row Retracted after
/// the one-time decision has passed (later checks, relaunches).
@property (nonatomic, nullable) CDRRetractionNotice *pendingRetraction;

#pragma mark Network (CND-7)

/// YES once the installed bundle's entitlements were looked at; the three
/// values below mean nothing until then.
@property (nonatomic) BOOL installedNetworkKnown;
/// What the installed build may do on the network (NSInteger-typed
/// CDRNetworkPosture, so this header doesn't pull the engine type in).
@property (nonatomic) NSInteger installedPosture;
@property (nonatomic, nullable) CDRInternetAccessPolicy *installedPolicy;
/// The sandbox / network entitlements the installed build holds, and its
/// Team ID — shown under the Developer interest scheme.
@property (nonatomic, copy, nullable) NSArray<NSString *> *installedEntitlementKeys;
@property (nonatomic, copy, nullable) NSString *teamID;
/// The verified, staged new build next to the installed one, when an
/// operation has inspected it.
@property (nonatomic, nullable) CDRNetworkInspection *inspection;
/// An operation Conductor started on its own to inspect the new build is
/// still downloading / verifying / reading.
@property (nonatomic) BOOL inspecting;
/// A verified build is parked at the approval step: its operation is
/// alive but doing nothing until the user answers.
@property (nonatomic) BOOL approvalParked;
/// …and the gate says that answer has to be asked for.
@property (nonatomic) BOOL networkApprovalNeeded;
@end

/// How the NETWORK row's status is drawn.
typedef NS_ENUM(NSInteger, CDRNetworkRowTone) {
    CDRNetworkRowToneNeutral = 0,
    /// Green: no access, or access dropped.
    CDRNetworkRowTonePositive,
    /// Amber: the new build gains access.
    CDRNetworkRowToneAttention,
};

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
/// When the withdrawn version was surfaced to the user, and when Conductor
/// saw it pulled — for the retraction pane's wording. Nil when unknown.
@property (nonatomic, readonly, nullable) NSDate *retractionAdvertisedDate;
@property (nonatomic, readonly, nullable) NSDate *retractionPulledDate;
/// The note types that put this row in Held, in the fixed order.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet heldTypes;
@property (nonatomic, readonly) CDRUpdatePhase operationPhase;
@property (nonatomic, readonly, nullable) NSString *errorDescription;
@property (nonatomic, readonly, nullable) NSString *developerName;
/// Categories shown in full for this app; the rest collapse to a one-line
/// count. Everything, unless the context carried the user's preferences.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet shownTypes;
/// The Developer interest scheme: also show manifest and entitlement detail.
@property (nonatomic, readonly) BOOL exposesDeveloperDetail;
/// The app's resolved deferral as the user reads it ("3 days"); nil when
/// the context carried no preferences or deferral is off.
@property (nonatomic, readonly, nullable) NSString *deferralDurationName;

#pragma mark NETWORK row

/// "No network access", "Has network access", "Gains internet access", …
@property (nonatomic, readonly) NSString *networkTitle;
/// "Same as 1.2 · this build makes no connections".
@property (nonatomic, readonly) NSString *networkDetail;
@property (nonatomic, readonly) CDRNetworkRowTone networkTone;
/// "Team ID matches" once a staged build has been verified; nil otherwise.
@property (nonatomic, readonly, nullable) NSString *networkTrailing;
/// The Internet Access Policy the row expands to: the staged build's when
/// it was inspected, otherwise the installed build's. Empty when none.
@property (nonatomic, readonly) NSArray<CDRInternetAccessPolicyRow *> *networkPolicyRows;
/// Raw entitlement keys and the Team ID, under the Developer scheme only.
@property (nonatomic, readonly) NSArray<NSString *> *networkDeveloperLines;

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
