//
//  CDRUpdatePolicy.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRManifest.h"

@class CDRAppRegistration;
@class CDRAppUpdateState;

@class CDRUpdatePreferences;

NS_ASSUME_NONNULL_BEGIN

/// How long a new version stays hidden (deferral.md): Off / 1 day / 3 days /
/// 1 week. Settings holds one value for all managed apps; an app may
/// override it (CDRAppPolicyOverride). The policy is always handed the
/// resolved value for the app it is deciding about.
typedef NS_ENUM(NSInteger, CDRSoakDuration) {
    CDRSoakDurationOff = 0,
    CDRSoakDurationOneDay,
    CDRSoakDurationOneWeek,
    /// Added in v2. Appended, not inserted, so the existing raw values and
    /// tokens are untouched; use CDRSoakDurationChoices() for display order.
    CDRSoakDurationThreeDays,
};

NSTimeInterval CDRSoakDurationInterval(CDRSoakDuration duration);

/// The durations in the order they are offered: Off, 1 day, 3 days, 1 week.
NSArray<NSNumber *> *CDRSoakDurationChoices(void);
/// "Off" / "1 day" / "3 days" / "1 week" — the user-facing name.
NSString *CDRSoakDurationDisplayName(CDRSoakDuration duration);

/// NSUserDefaults token round-trip ("off" / "1d" / "3d" / "1w"); garbage → Off.
CDRSoakDuration CDRSoakDurationFromDefaultsToken(NSString * _Nullable token);
NSString *CDRSoakDurationDefaultsToken(CDRSoakDuration duration);

/// The NSUserDefaults key holding the soak token. The key and token format are
/// the durable contract. It is the Settings-wide value; per-app overrides live
/// under CDRAppPolicyOverridesDefaultsKey (CDRUpdatePreferences.h).
/// "Soak" is spec/internal terminology (deferral.md) — user-facing copy says
/// "deferred" / "update settings", never "soak".
extern NSString * const CDRSoakDurationDefaultsKey;

/// Outcome of evaluating one fresh manifest against one app's memory. Every
/// row of the deferral.md + retraction.md state tables maps to exactly one of
/// these.
typedef NS_ENUM(NSInteger, CDRUpdateOutcome) {
    CDRUpdateOutcomeUpToDate = 0,
    /// Surface now (soak off, matured, urgency bypass, or re-show).
    CDRUpdateOutcomeAvailable,
    /// Soaking and hidden; deferredUntil says when it matures.
    CDRUpdateOutcomeDeferred,
    /// Break-through: still soaking, but offered honestly ("deferred until
    /// <date> by your update settings — install anyway?").
    CDRUpdateOutcomeDeferredOffered,
    /// Retraction State A: a version the user was told about vanished and is
    /// not installed. Loud once, then cleared.
    CDRUpdateOutcomeRetractedPending,
    /// Retraction State B: the retracted build is what's installed. Inform,
    /// never auto-downgrade; persists until the manifest advertises ≥ installed.
    CDRUpdateOutcomeRetractedInstalled,
    /// A never-surfaced (still-soaking) version vanished. Presents to the user
    /// identically to UpToDate — the distinct value exists so tests can assert
    /// the silence (retraction.md: no promise was made, no correction is owed).
    CDRUpdateOutcomeDroppedSilently,
    /// A surfaced update that contains a note type the user installs by hand
    /// (`heldTypes`). Installable, but only on a deliberate click.
    CDRUpdateOutcomeHeld,
    /// A surfaced update whose leading version component is greater than the
    /// installed one's, while the user stops at major versions. Takes the
    /// state line over Held; `heldTypes` still says whether a hold applies too.
    CDRUpdateOutcomeStoppedAtMajor,
    /// The user chose "Skip this version" for exactly this version. Quiet:
    /// not notified, not installable, until a different version is
    /// advertised or the user checks this app by hand (a break-through).
    CDRUpdateOutcomeSkipped,
};

/// What one check concluded, plus the record to persist afterward.
@interface CDRUpdateDecision : NSObject
@property (nonatomic, readonly) CDRUpdateOutcome outcome;
/// Populated for Deferred / DeferredOffered.
@property (nonatomic, readonly, nullable) NSDate *deferredUntil;
/// Populated for RetractedPending / RetractedInstalled.
@property (nonatomic, readonly, nullable) NSString *retractedVersion;
/// Copied from the manifest so the caller can render the urgency notice.
@property (nonatomic, readonly) CDRUrgency urgency;
/// The user's hold categories present in this update — the advertised
/// release or any skipped one. Set on Held and StoppedAtMajor, empty otherwise.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet heldTypes;
/// Whether the major-version stop applies (YES exactly on StoppedAtMajor).
@property (nonatomic, readonly) BOOL stoppedAtMajor;
/// The record to persist after this check: ingestion always, notified-marking
/// on Available, clearing on State A. A DeferredOffered decision does NOT
/// mark notified — that happens only on the user's install consent
/// (CDRUpdateStateStore -noteNotifiedVersion:…).
@property (nonatomic, readonly) CDRAppUpdateState *stateAfterCheck;
@end

/// The pure decision function: (registration, manifest, stored state, the
/// app's resolved preferences, break-through, now) → decision.
///
/// Order: deferral is evaluated first (hidden is hidden). Only an update
/// that would otherwise be surfaced is then checked against the user's two
/// gates — the major-version stop, then the hold categories. Urgency is the
/// vendor's claim and bypasses deferral only; it never bypasses a gate the
/// user set. No I/O, no defaults, no clock —
/// every transition in the deferral.md / retraction.md state tables is
/// unit-testable offline. Nothing below this layer (the update operation and
/// its verification chain) ever sees soak, urgency, or stored state.
@interface CDRUpdatePolicy : NSObject

+ (CDRUpdateDecision *)decisionForRegistration:(CDRAppRegistration *)registration
                                      manifest:(CDRManifest *)manifest
                                         state:(nullable CDRAppUpdateState *)state
                                   preferences:(CDRUpdatePreferences *)preferences
                                  breakThrough:(BOOL)breakThrough
                                           now:(NSDate *)now;

@end

/// Fixed, Conductor-owned copy — centralized here the way error copy is
/// centralized in CDRErrors.m. Retraction States A/B and the deferral offer
/// are informational, deliberately not NSErrors.
///
/// Urgency copy is rendered as the *vendor's* claim ("The developer has
/// flagged …"): the manifest is unauthenticated, so attributing the assertion
/// bounds a forged flag's damage to embarrassment, not compromise (deferral.md).
/// Why a surfaced update is waiting on the user, as one sentence:
/// "Held because it includes a removal." / "1.0 is a major version; you stop
/// at major versions." — the major stop first when both apply.
NSString *CDRUpdateGateReasonCopy(CDRUpdateDecision *decision, NSString *installedVersion, NSString *version);

NSString *CDRUrgencyNoticeCopy(CDRUrgency urgency, NSString *appName, NSString *version);
NSString *CDRDeferredOfferCopy(NSString *appName, NSString *version, NSDate *deferredUntil);
NSString *CDRRetractedPendingCopy(NSString *appName, NSString *retractedVersion, NSString *installedVersion);
NSString *CDRRetractedInstalledCopy(NSString *appName, NSString *retractedVersion);

NS_ASSUME_NONNULL_END
