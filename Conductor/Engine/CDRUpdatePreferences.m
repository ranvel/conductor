//
//  CDRUpdatePreferences.m
//  Conductor
//

#import "CDRUpdatePreferences.h"

NSString * const CDRStopAtMajorVersionsDefaultsKey = @"CDRStopAtMajorVersions";
NSString * const CDRInterestSchemeDefaultsKey = @"CDRInterestScheme";
NSString * const CDRShownNoteTypesDefaultsKey = @"CDRShownNoteTypes";
NSString * const CDRHoldNoteTypesDefaultsKey = @"CDRHoldNoteTypes";
NSString * const CDRRequireNetworkApprovalDefaultsKey = @"CDRRequireNetworkApproval";
NSString * const CDRPolicyExemptsNetworkApprovalDefaultsKey = @"CDRPolicyExemptsNetworkApproval";
NSString * const CDRAppPolicyOverridesDefaultsKey = @"CDRAppPolicyOverrides";

const CDRReleaseNoteTypeSet CDRDefaultHoldTypes =
    CDRReleaseNoteTypeSetNotice | CDRReleaseNoteTypeSetRemoved | CDRReleaseNoteTypeSetRetracted;

NSString *CDRInterestSchemeDefaultsToken(CDRInterestScheme scheme) {
    switch (scheme) {
        case CDRInterestSchemeNormal: return @"normal";
        case CDRInterestSchemeEverything: return @"everything";
        case CDRInterestSchemeDeveloper: return @"developer";
        case CDRInterestSchemeCustom: return @"custom";
    }
    return @"normal";
}

CDRInterestScheme CDRInterestSchemeFromDefaultsToken(NSString *token) {
    if ([token isKindOfClass:[NSString class]]) {
        if ([token isEqualToString:@"everything"]) return CDRInterestSchemeEverything;
        if ([token isEqualToString:@"developer"]) return CDRInterestSchemeDeveloper;
        if ([token isEqualToString:@"custom"]) return CDRInterestSchemeCustom;
    }
    return CDRInterestSchemeNormal;
}

CDRReleaseNoteTypeSet CDRShownTypesForInterestScheme(CDRInterestScheme scheme) {
    switch (scheme) {
        case CDRInterestSchemeNormal:
            return CDRReleaseNoteTypeSetAll & ~CDRReleaseNoteTypeSetSecurity;
        case CDRInterestSchemeEverything:
        case CDRInterestSchemeDeveloper:
        case CDRInterestSchemeCustom:
            return CDRReleaseNoteTypeSetAll;
    }
    return CDRReleaseNoteTypeSetAll;
}

/// Retracted is Conductor's own row: always shown, always a hold. Applied on
/// every path a type set enters a preferences object, so no stored value —
/// and no `defaults write` — can switch it off.
static CDRReleaseNoteTypeSet WithRetracted(CDRReleaseNoteTypeSet set) {
    return (set & CDRReleaseNoteTypeSetAll) | CDRReleaseNoteTypeSetRetracted;
}

/// A stored BOOL, or `fallback` when the key is absent or not a number.
static BOOL StoredBool(NSUserDefaults *defaults, NSString *key, BOOL fallback) {
    id value = [defaults objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

#pragma mark - CDRUpdatePreferences

@interface CDRUpdatePreferences () {
@protected
    CDRSoakDuration _soakDuration;
    BOOL _stopAtMajorVersions;
    CDRInterestScheme _interestScheme;
    CDRReleaseNoteTypeSet _shownTypes;
    CDRReleaseNoteTypeSet _holdTypes;
    BOOL _requireNetworkApproval;
    BOOL _policyExemptsApproval;
}
@end

@interface CDRMutableUpdatePreferences ()
/// An app's own categories: replaces the set but keeps the user's scheme.
- (void)setShownTypesKeepingScheme:(CDRReleaseNoteTypeSet)shownTypes;
@end

@implementation CDRUpdatePreferences

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _soakDuration = CDRSoakDurationOff;
    _stopAtMajorVersions = NO;
    _interestScheme = CDRInterestSchemeNormal;
    _shownTypes = WithRetracted(CDRShownTypesForInterestScheme(CDRInterestSchemeNormal));
    _holdTypes = WithRetracted(CDRDefaultHoldTypes);
    _requireNetworkApproval = YES;
    _policyExemptsApproval = YES;
    return self;
}

+ (instancetype)defaultPreferences {
    return [[CDRUpdatePreferences alloc] init];
}

+ (instancetype)preferencesFromDefaults:(NSUserDefaults *)defaults {
    CDRUpdatePreferences *p = [[CDRUpdatePreferences alloc] init];
    p->_soakDuration = CDRSoakDurationFromDefaultsToken([defaults stringForKey:CDRSoakDurationDefaultsKey]);
    p->_stopAtMajorVersions = StoredBool(defaults, CDRStopAtMajorVersionsDefaultsKey, NO);
    p->_interestScheme = CDRInterestSchemeFromDefaultsToken([defaults stringForKey:CDRInterestSchemeDefaultsKey]);

    if (p->_interestScheme == CDRInterestSchemeCustom) {
        // Only a custom scheme reads the stored set; a preset always means
        // exactly its own categories, whatever else is on disk.
        id stored = [defaults objectForKey:CDRShownNoteTypesDefaultsKey];
        p->_shownTypes = [stored isKindOfClass:[NSArray class]]
            ? WithRetracted(CDRReleaseNoteTypeSetFromKeys(stored))
            : WithRetracted(CDRReleaseNoteTypeSetAll);
    } else {
        p->_shownTypes = WithRetracted(CDRShownTypesForInterestScheme(p->_interestScheme));
    }

    id hold = [defaults objectForKey:CDRHoldNoteTypesDefaultsKey];
    p->_holdTypes = [hold isKindOfClass:[NSArray class]]
        ? WithRetracted(CDRReleaseNoteTypeSetFromKeys(hold))
        : WithRetracted(CDRDefaultHoldTypes);

    p->_requireNetworkApproval = StoredBool(defaults, CDRRequireNetworkApprovalDefaultsKey, YES);
    p->_policyExemptsApproval = StoredBool(defaults, CDRPolicyExemptsNetworkApprovalDefaultsKey, YES);
    return p;
}

- (void)writeToDefaults:(NSUserDefaults *)defaults {
    [defaults setObject:CDRSoakDurationDefaultsToken(self.soakDuration) forKey:CDRSoakDurationDefaultsKey];
    [defaults setBool:self.stopAtMajorVersions forKey:CDRStopAtMajorVersionsDefaultsKey];
    [defaults setObject:CDRInterestSchemeDefaultsToken(self.interestScheme) forKey:CDRInterestSchemeDefaultsKey];
    [defaults setObject:CDRReleaseNoteKeysFromTypeSet(self.shownTypes) forKey:CDRShownNoteTypesDefaultsKey];
    [defaults setObject:CDRReleaseNoteKeysFromTypeSet(self.holdTypes) forKey:CDRHoldNoteTypesDefaultsKey];
    [defaults setBool:self.requireNetworkApproval forKey:CDRRequireNetworkApprovalDefaultsKey];
    [defaults setBool:self.policyExemptsApproval forKey:CDRPolicyExemptsNetworkApprovalDefaultsKey];
}

- (CDRSoakDuration)soakDuration { return _soakDuration; }
- (BOOL)stopAtMajorVersions { return _stopAtMajorVersions; }
- (CDRInterestScheme)interestScheme { return _interestScheme; }
- (CDRReleaseNoteTypeSet)shownTypes { return _shownTypes; }
- (CDRReleaseNoteTypeSet)holdTypes { return _holdTypes; }
- (BOOL)requireNetworkApproval { return _requireNetworkApproval; }
- (BOOL)policyExemptsApproval { return _policyExemptsApproval; }
- (BOOL)exposesDeveloperDetail { return _interestScheme == CDRInterestSchemeDeveloper; }

- (void)copyFieldsInto:(CDRUpdatePreferences *)other {
    other->_soakDuration = _soakDuration;
    other->_stopAtMajorVersions = _stopAtMajorVersions;
    other->_interestScheme = _interestScheme;
    other->_shownTypes = WithRetracted(_shownTypes);
    other->_holdTypes = WithRetracted(_holdTypes);
    other->_requireNetworkApproval = _requireNetworkApproval;
    other->_policyExemptsApproval = _policyExemptsApproval;
}

- (id)copyWithZone:(NSZone *)zone {
    CDRUpdatePreferences *copy = [[CDRUpdatePreferences alloc] init];
    [self copyFieldsInto:copy];
    return copy;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    CDRMutableUpdatePreferences *copy = [[CDRMutableUpdatePreferences alloc] init];
    [self copyFieldsInto:copy];
    return copy;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CDRUpdatePreferences class]]) return NO;
    CDRUpdatePreferences *o = object;
    return _soakDuration == o->_soakDuration && _stopAtMajorVersions == o->_stopAtMajorVersions
        && _interestScheme == o->_interestScheme && _shownTypes == o->_shownTypes
        && _holdTypes == o->_holdTypes && _requireNetworkApproval == o->_requireNetworkApproval
        && _policyExemptsApproval == o->_policyExemptsApproval;
}

- (NSUInteger)hash {
    return (NSUInteger)_soakDuration ^ (_shownTypes << 4) ^ (_holdTypes << 12) ^ ((NSUInteger)_interestScheme << 20);
}

@end

@implementation CDRMutableUpdatePreferences

@dynamic soakDuration, stopAtMajorVersions, interestScheme, shownTypes, holdTypes,
         requireNetworkApproval, policyExemptsApproval;

- (void)setSoakDuration:(CDRSoakDuration)soakDuration { _soakDuration = soakDuration; }
- (void)setStopAtMajorVersions:(BOOL)stop { _stopAtMajorVersions = stop; }

- (void)setInterestScheme:(CDRInterestScheme)scheme {
    _interestScheme = scheme;
    if (scheme != CDRInterestSchemeCustom) {
        _shownTypes = WithRetracted(CDRShownTypesForInterestScheme(scheme));
    }
}

- (void)setShownTypes:(CDRReleaseNoteTypeSet)shownTypes {
    // Editing the grid by hand leaves no preset selected.
    _shownTypes = WithRetracted(shownTypes);
    _interestScheme = CDRInterestSchemeCustom;
}

- (void)setShownTypesKeepingScheme:(CDRReleaseNoteTypeSet)shownTypes {
    _shownTypes = WithRetracted(shownTypes);
}

- (void)setHoldTypes:(CDRReleaseNoteTypeSet)holdTypes { _holdTypes = WithRetracted(holdTypes); }
- (void)setRequireNetworkApproval:(BOOL)require { _requireNetworkApproval = require; }
- (void)setPolicyExemptsApproval:(BOOL)exempts { _policyExemptsApproval = exempts; }

@end

#pragma mark - CDRAppPolicyOverride

static NSString * const kOverrideSoakKey = @"defer";
static NSString * const kOverrideStopAtMajorKey = @"stop_at_major";
static NSString * const kOverrideShownKey = @"shown";
static NSString * const kOverrideHoldKey = @"hold";

@implementation CDRAppPolicyOverride

+ (instancetype)overrideWithDictionary:(id)dictionary {
    CDRAppPolicyOverride *override = [[CDRAppPolicyOverride alloc] init];
    if (![dictionary isKindOfClass:[NSDictionary class]]) return override;
    NSDictionary *dict = dictionary;

    // A deferral token must be one Conductor writes; an unknown token is
    // "no override", not "Off".
    NSString *token = dict[kOverrideSoakKey];
    if ([token isKindOfClass:[NSString class]]) {
        for (NSNumber *choice in CDRSoakDurationChoices()) {
            if ([CDRSoakDurationDefaultsToken((CDRSoakDuration)choice.integerValue) isEqualToString:token]) {
                override.soakDuration = choice;
            }
        }
    }
    id stop = dict[kOverrideStopAtMajorKey];
    if ([stop isKindOfClass:[NSNumber class]]) override.stopAtMajorVersions = @([stop boolValue]);
    id shown = dict[kOverrideShownKey];
    if ([shown isKindOfClass:[NSArray class]]) {
        override.shownTypes = @(WithRetracted(CDRReleaseNoteTypeSetFromKeys(shown)));
    }
    id hold = dict[kOverrideHoldKey];
    if ([hold isKindOfClass:[NSArray class]]) {
        override.holdTypes = @(WithRetracted(CDRReleaseNoteTypeSetFromKeys(hold)));
    }
    return override;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary<NSString *, id> *dict = [NSMutableDictionary dictionary];
    if (self.soakDuration) {
        dict[kOverrideSoakKey] = CDRSoakDurationDefaultsToken((CDRSoakDuration)self.soakDuration.integerValue);
    }
    if (self.stopAtMajorVersions) dict[kOverrideStopAtMajorKey] = @(self.stopAtMajorVersions.boolValue);
    if (self.shownTypes) {
        dict[kOverrideShownKey] = CDRReleaseNoteKeysFromTypeSet(WithRetracted(self.shownTypes.unsignedIntegerValue));
    }
    if (self.holdTypes) {
        dict[kOverrideHoldKey] = CDRReleaseNoteKeysFromTypeSet(WithRetracted(self.holdTypes.unsignedIntegerValue));
    }
    return dict;
}

- (BOOL)isEmpty {
    return !self.soakDuration && !self.stopAtMajorVersions && !self.shownTypes && !self.holdTypes;
}

- (id)copyWithZone:(NSZone *)zone {
    CDRAppPolicyOverride *copy = [[CDRAppPolicyOverride alloc] init];
    copy.soakDuration = self.soakDuration;
    copy.stopAtMajorVersions = self.stopAtMajorVersions;
    copy.shownTypes = self.shownTypes;
    copy.holdTypes = self.holdTypes;
    return copy;
}

@end

CDRAppPolicyOverride *CDRAppPolicyOverrideForBundleID(NSString *bundleID, NSUserDefaults *defaults) {
    id all = [defaults objectForKey:CDRAppPolicyOverridesDefaultsKey];
    id entry = [all isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)all)[bundleID] : nil;
    return [CDRAppPolicyOverride overrideWithDictionary:entry];
}

void CDRSetAppPolicyOverride(CDRAppPolicyOverride *override, NSString *bundleID, NSUserDefaults *defaults) {
    id stored = [defaults objectForKey:CDRAppPolicyOverridesDefaultsKey];
    NSMutableDictionary *all = [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (!override || override.isEmpty) {
        [all removeObjectForKey:bundleID];
    } else {
        all[bundleID] = [override dictionaryRepresentation];
    }
    if (all.count == 0) {
        [defaults removeObjectForKey:CDRAppPolicyOverridesDefaultsKey];
    } else {
        [defaults setObject:all forKey:CDRAppPolicyOverridesDefaultsKey];
    }
}

#pragma mark - CDRPolicyResolver

@implementation CDRPolicyResolver

+ (CDRUpdatePreferences *)effectivePreferencesWithGlobal:(CDRUpdatePreferences *)global
                                                override:(CDRAppPolicyOverride *)override {
    CDRMutableUpdatePreferences *effective = [global mutableCopy];
    if (override.soakDuration) {
        effective.soakDuration = (CDRSoakDuration)override.soakDuration.integerValue;
    }
    if (override.stopAtMajorVersions) {
        effective.stopAtMajorVersions = override.stopAtMajorVersions.boolValue;
    }
    if (override.shownTypes) {
        // The app's own categories. The global scheme stays the scheme:
        // Developer detail is a property of the user, not of one app.
        [effective setShownTypesKeepingScheme:override.shownTypes.unsignedIntegerValue];
    }
    if (override.holdTypes) {
        effective.holdTypes = override.holdTypes.unsignedIntegerValue;
    }
    return [effective copy];
}

+ (CDRUpdatePreferences *)effectivePreferencesForBundleID:(NSString *)bundleID
                                                 defaults:(NSUserDefaults *)defaults {
    return [self effectivePreferencesWithGlobal:[CDRUpdatePreferences preferencesFromDefaults:defaults]
                                       override:CDRAppPolicyOverrideForBundleID(bundleID, defaults)];
}

@end

#pragma mark - Wording

static NSString *JoinedWithAnd(NSArray<NSString *> *items) {
    if (items.count <= 1) return items.firstObject ?: @"";
    if (items.count == 2) return [NSString stringWithFormat:@"%@ and %@", items[0], items[1]];
    NSArray<NSString *> *head = [items subarrayWithRange:NSMakeRange(0, items.count - 1)];
    return [NSString stringWithFormat:@"%@ and %@", [head componentsJoinedByString:@", "], items.lastObject];
}

NSString *CDRTypeSetOverrideSummary(CDRReleaseNoteTypeSet global, CDRReleaseNoteTypeSet overridden,
                                    NSString *addedWord, NSString *removedWord, NSString *appName) {
    global = WithRetracted(global);
    overridden = WithRetracted(overridden);
    if (global == overridden) return @"Same as Settings";

    NSString *added = CDRReleaseNoteTypeSetDisplayList(overridden & ~global);
    NSString *removed = CDRReleaseNoteTypeSetDisplayList(global & ~overridden);
    NSMutableArray<NSString *> *clauses = [NSMutableArray array];
    if (added.length > 0) [clauses addObject:[NSString stringWithFormat:@"%@ %@", added, addedWord]];
    if (removed.length > 0) [clauses addObject:[NSString stringWithFormat:@"%@ %@", removed, removedWord]];
    return [NSString stringWithFormat:@"%@ for %@ only", JoinedWithAnd(clauses), appName];
}

NSString *CDRSettingsEchoForSoakDuration(CDRSoakDuration duration) {
    NSString *name = CDRSoakDurationDisplayName(duration);
    return [@"Settings: " stringByAppendingString:(duration == CDRSoakDurationOff ? @"off" : name)];
}

NSString *CDRSettingsEchoForBool(BOOL value) {
    return value ? @"Settings: on" : @"Settings: off";
}

NSString *CDRSettingsEchoForTypeSet(CDRReleaseNoteTypeSet set) {
    return [@"Settings: " stringByAppendingString:CDRReleaseNoteTypeSetDisplayList(WithRetracted(set))];
}
