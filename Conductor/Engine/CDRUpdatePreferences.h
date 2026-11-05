//
//  CDRUpdatePreferences.h
//  Conductor
//
//  Every v2 user policy as values: the global preferences, a per-app
//  override, and the resolver that combines them. Pure — the only I/O is
//  the NSUserDefaults round-trip, kept in this one file.
//

#import <Foundation/Foundation.h>
#import "CDRReleaseNote.h"
#import "CDRUpdatePolicy.h"

NS_ASSUME_NONNULL_BEGIN

/// What the user wants to read. A preset decides `shownTypes`; Custom means
/// the user edited the category grid themselves.
typedef NS_ENUM(NSInteger, CDRInterestScheme) {
    /// What changes how you use the app. Security details collapse.
    CDRInterestSchemeNormal = 0,
    /// Every note in every category.
    CDRInterestSchemeEverything,
    /// Everything, plus manifest and entitlement detail.
    CDRInterestSchemeDeveloper,
    /// The user's own choice of categories; no preset is selected.
    CDRInterestSchemeCustom,
};

NSString *CDRInterestSchemeDefaultsToken(CDRInterestScheme scheme);
/// Garbage → Normal.
CDRInterestScheme CDRInterestSchemeFromDefaultsToken(NSString * _Nullable token);
/// The categories a preset shows in full. Custom has no preset and returns
/// everything; its real value is the stored set.
CDRReleaseNoteTypeSet CDRShownTypesForInterestScheme(CDRInterestScheme scheme);

#pragma mark Defaults keys (the key and its value format are the durable contract)

// CDRSoakDurationDefaultsKey (CDRUpdatePolicy.h) holds the deferral token.
extern NSString * const CDRStopAtMajorVersionsDefaultsKey;        // BOOL, default NO
extern NSString * const CDRInterestSchemeDefaultsKey;             // "normal" / "everything" / "developer" / "custom"
extern NSString * const CDRShownNoteTypesDefaultsKey;             // [type keys]; read only when the scheme is custom
extern NSString * const CDRHoldNoteTypesDefaultsKey;              // [type keys]; default notice, removed, retracted
extern NSString * const CDRRequireNetworkApprovalDefaultsKey;     // BOOL, default YES
extern NSString * const CDRPolicyExemptsNetworkApprovalDefaultsKey; // BOOL, default YES
extern NSString * const CDRAppPolicyOverridesDefaultsKey;         // { bundleID: override dictionary }

/// The categories that hold an update when nothing is stored.
extern const CDRReleaseNoteTypeSet CDRDefaultHoldTypes;

@class CDRMutableUpdatePreferences;

/// One immutable set of preferences: either the user's global Settings, or
/// the effective values for one app after its override is applied.
///
/// Invariant, enforced on every construction path regardless of what is
/// stored: Retracted is always in `shownTypes` and in `holdTypes`.
@interface CDRUpdatePreferences : NSObject <NSCopying, NSMutableCopying>

@property (nonatomic, readonly) CDRSoakDuration soakDuration;
@property (nonatomic, readonly) BOOL stopAtMajorVersions;
@property (nonatomic, readonly) CDRInterestScheme interestScheme;
/// Categories shown in full; the rest collapse to a one-line count.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet shownTypes;
/// Categories that hold an update for a deliberate install.
@property (nonatomic, readonly) CDRReleaseNoteTypeSet holdTypes;
@property (nonatomic, readonly) BOOL requireNetworkApproval;
/// "…unless it ships an Internet Access Policy". Meaningful only while
/// `requireNetworkApproval` is on.
@property (nonatomic, readonly) BOOL policyExemptsApproval;
/// The Developer scheme: also show manifest and entitlement detail.
@property (nonatomic, readonly) BOOL exposesDeveloperDetail;

/// What a fresh install uses.
+ (instancetype)defaultPreferences;
/// Reads the global Settings. Missing or garbage values fall back to the
/// defaults field by field.
+ (instancetype)preferencesFromDefaults:(NSUserDefaults *)defaults;
- (void)writeToDefaults:(NSUserDefaults *)defaults;

@end

/// The mutable twin, for building a changed copy:
/// `CDRMutableUpdatePreferences *p = [prefs mutableCopy]; p.x = …; [p copy]`.
@interface CDRMutableUpdatePreferences : CDRUpdatePreferences
@property (nonatomic, readwrite) CDRSoakDuration soakDuration;
@property (nonatomic, readwrite) BOOL stopAtMajorVersions;
/// Setting a preset also sets `shownTypes` to that preset's categories.
@property (nonatomic, readwrite) CDRInterestScheme interestScheme;
/// Setting this makes the scheme Custom.
@property (nonatomic, readwrite) CDRReleaseNoteTypeSet shownTypes;
@property (nonatomic, readwrite) CDRReleaseNoteTypeSet holdTypes;
@property (nonatomic, readwrite) BOOL requireNetworkApproval;
@property (nonatomic, readwrite) BOOL policyExemptsApproval;
@end

/// What one app does differently from Settings. Every field is optional;
/// nil means "follow Settings". Covers the four policies the per-app popover
/// offers — the network gate has no per-app override.
@interface CDRAppPolicyOverride : NSObject <NSCopying>

/// NSNumber-wrapped CDRSoakDuration.
@property (nonatomic, copy, nullable) NSNumber *soakDuration;
/// NSNumber-wrapped BOOL.
@property (nonatomic, copy, nullable) NSNumber *stopAtMajorVersions;
/// NSNumber-wrapped CDRReleaseNoteTypeSet. Nil follows the interest scheme.
@property (nonatomic, copy, nullable) NSNumber *shownTypes;
/// NSNumber-wrapped CDRReleaseNoteTypeSet.
@property (nonatomic, copy, nullable) NSNumber *holdTypes;

/// YES when nothing is overridden — such an override is never stored.
@property (nonatomic, readonly) BOOL isEmpty;

/// Garbage-tolerant: unknown or malformed entries are ignored, so a bad
/// `defaults write` can only ever fall back to Settings.
+ (instancetype)overrideWithDictionary:(nullable id)dictionary;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

/// The stored override for an app; empty (never nil) when there is none.
CDRAppPolicyOverride *CDRAppPolicyOverrideForBundleID(NSString *bundleID, NSUserDefaults *defaults);
/// Stores the override. Nil or an empty override removes the app's entry
/// entirely ("Reset to Settings").
void CDRSetAppPolicyOverride(CDRAppPolicyOverride * _Nullable override, NSString *bundleID, NSUserDefaults *defaults);

@interface CDRPolicyResolver : NSObject

/// override ∘ global. Pure. Fields the override leaves nil come from
/// `global`; Retracted is forced into both type sets either way.
+ (CDRUpdatePreferences *)effectivePreferencesWithGlobal:(CDRUpdatePreferences *)global
                                                override:(nullable CDRAppPolicyOverride *)override;

/// The effective preferences for one app, read from defaults.
+ (CDRUpdatePreferences *)effectivePreferencesForBundleID:(NSString *)bundleID
                                                 defaults:(NSUserDefaults *)defaults;

@end

#pragma mark Wording for the per-app popover (pure)

/// How an overridden type set differs from Settings, as one line:
/// "Security shown and Fixed hidden for muwav only". `addedWord` describes
/// types the override adds ("shown", "held"), `removedWord` the ones it
/// drops ("hidden", "not held"). Returns "Same as Settings" when equal.
NSString *CDRTypeSetOverrideSummary(CDRReleaseNoteTypeSet global, CDRReleaseNoteTypeSet overridden,
                                    NSString *addedWord, NSString *removedWord, NSString *appName);

/// "Settings: 3 days", "Settings: off", "Settings: on".
NSString *CDRSettingsEchoForSoakDuration(CDRSoakDuration duration);
NSString *CDRSettingsEchoForBool(BOOL value);
/// "Settings: Notice, Removed, Retracted".
NSString *CDRSettingsEchoForTypeSet(CDRReleaseNoteTypeSet set);

NS_ASSUME_NONNULL_END
