//
//  CDRUpdatePolicy.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRManifest.h"

@class CDRAppRegistration;
@class CDRAppUpdateState;

NS_ASSUME_NONNULL_BEGIN

/// The global soak setting (deferral.md): Off / 1 day / 1 week, one value for
/// all managed apps, no per-app overrides.
typedef NS_ENUM(NSInteger, CDRSoakDuration) {
    CDRSoakDurationOff = 0,
    CDRSoakDurationOneDay,
    CDRSoakDurationOneWeek,
};

NSTimeInterval CDRSoakDurationInterval(CDRSoakDuration duration);

/// NSUserDefaults token round-trip ("off" / "1d" / "1w"); garbage → Off.
CDRSoakDuration CDRSoakDurationFromDefaultsToken(NSString * _Nullable token);
NSString *CDRSoakDurationDefaultsToken(CDRSoakDuration duration);

/// The NSUserDefaults key holding the soak token. The key and token format are
/// the durable contract. Until the M3 preferences panel exists this is set via
/// `defaults write`; there is deliberately no control on the main window.
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
/// The record to persist after this check: ingestion always, notified-marking
/// on Available, clearing on State A. A DeferredOffered decision does NOT
/// mark notified — that happens only on the user's install consent
/// (CDRUpdateStateStore -noteNotifiedVersion:…).
@property (nonatomic, readonly) CDRAppUpdateState *stateAfterCheck;
@end

/// The pure decision function: (registration, manifest, stored state, soak
/// setting, break-through, now) → decision. No I/O, no defaults, no clock —
/// every transition in the deferral.md / retraction.md state tables is
/// unit-testable offline. Nothing below this layer (the update operation and
/// its verification chain) ever sees soak, urgency, or stored state.
@interface CDRUpdatePolicy : NSObject

+ (CDRUpdateDecision *)decisionForRegistration:(CDRAppRegistration *)registration
                                      manifest:(CDRManifest *)manifest
                                         state:(nullable CDRAppUpdateState *)state
                                  soakDuration:(CDRSoakDuration)soakDuration
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
NSString *CDRUrgencyNoticeCopy(CDRUrgency urgency, NSString *appName, NSString *version);
NSString *CDRDeferredOfferCopy(NSString *appName, NSString *version, NSDate *deferredUntil);
NSString *CDRRetractedPendingCopy(NSString *appName, NSString *retractedVersion, NSString *installedVersion);
NSString *CDRRetractedInstalledCopy(NSString *appName, NSString *retractedVersion);

NS_ASSUME_NONNULL_END
