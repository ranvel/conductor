//
//  CDRReleaseNote.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The closed release-note vocabulary (spec.md §3.5). Declared in the fixed
/// render order — what takes something away comes first — so sorting by type
/// is sorting by enum value. The manifest carries only a lowercase key and
/// plain text; Conductor draws every badge.
typedef NS_ENUM(NSInteger, CDRReleaseNoteType) {
    CDRReleaseNoteTypeNotice = 0,
    CDRReleaseNoteTypeRemoved,
    CDRReleaseNoteTypeDisabled,
    CDRReleaseNoteTypeSecurity,
    CDRReleaseNoteTypeAdded,
    CDRReleaseNoteTypeImproved,
    CDRReleaseNoteTypeFixed,
    /// Conductor-generated only. Never accepted from a manifest: a forged
    /// "retracted" item is dropped like any unknown type.
    CDRReleaseNoteTypeRetracted,
};

/// Number of values in CDRReleaseNoteType (for iteration in render order).
extern const NSInteger CDRReleaseNoteTypeCount;

/// A set of note types (which categories are present, shown, or held).
typedef NS_OPTIONS(NSUInteger, CDRReleaseNoteTypeSet) {
    CDRReleaseNoteTypeSetNone      = 0,
    CDRReleaseNoteTypeSetNotice    = 1 << CDRReleaseNoteTypeNotice,
    CDRReleaseNoteTypeSetRemoved   = 1 << CDRReleaseNoteTypeRemoved,
    CDRReleaseNoteTypeSetDisabled  = 1 << CDRReleaseNoteTypeDisabled,
    CDRReleaseNoteTypeSetSecurity  = 1 << CDRReleaseNoteTypeSecurity,
    CDRReleaseNoteTypeSetAdded     = 1 << CDRReleaseNoteTypeAdded,
    CDRReleaseNoteTypeSetImproved  = 1 << CDRReleaseNoteTypeImproved,
    CDRReleaseNoteTypeSetFixed     = 1 << CDRReleaseNoteTypeFixed,
    CDRReleaseNoteTypeSetRetracted = 1 << CDRReleaseNoteTypeRetracted,
    /// The seven types a developer may write.
    CDRReleaseNoteTypeSetDeveloperAuthored = (1 << CDRReleaseNoteTypeRetracted) - 1,
    CDRReleaseNoteTypeSetAll = (1 << (CDRReleaseNoteTypeRetracted + 1)) - 1,
};

CDRReleaseNoteTypeSet CDRReleaseNoteTypeSetWithType(CDRReleaseNoteType type);
BOOL CDRReleaseNoteTypeSetContains(CDRReleaseNoteTypeSet set, CDRReleaseNoteType type);

/// A type set ↔ its keys, for persistence. Reading is garbage-tolerant:
/// anything that is not an array of known keys contributes nothing.
NSArray<NSString *> *CDRReleaseNoteKeysFromTypeSet(CDRReleaseNoteTypeSet set);
CDRReleaseNoteTypeSet CDRReleaseNoteTypeSetFromKeys(id _Nullable keys);
/// "Notice, Removed, Retracted" — the set's display names in the fixed order.
NSString *CDRReleaseNoteTypeSetDisplayList(CDRReleaseNoteTypeSet set);

/// Canonical lowercase key ↔ enum, in one place. Matching is exact: an
/// unknown key is rejected, never guessed at.
NSString *CDRReleaseNoteTypeKey(CDRReleaseNoteType type);
BOOL CDRReleaseNoteTypeFromKey(NSString * _Nullable key, CDRReleaseNoteType * _Nullable outType);

/// The badge label ("Notice", "Removed", …).
NSString *CDRReleaseNoteTypeDisplayName(CDRReleaseNoteType type);

/// The type as a thing an update "includes": "a removal", "a security fix", …
/// Used where one type has to be named in a sentence.
NSString *CDRReleaseNoteTypeNounPhrase(CDRReleaseNoteType type);

/// A counted phrase for a collapsed category: "2 security fixes", "1 removal".
NSString *CDRReleaseNoteTypeCountPhrase(CDRReleaseNoteType type, NSUInteger count);

/// YES for the seven types a manifest may carry; NO for Retracted.
BOOL CDRReleaseNoteTypeIsDeveloperAuthored(CDRReleaseNoteType type);

/// The longest note text Conductor keeps; longer text is truncated.
extern const NSUInteger CDRReleaseNoteMaxTextLength;

/// Plain-text rule: whitespace (including newlines and control characters)
/// collapses to single spaces, the result is trimmed and capped at
/// CDRReleaseNoteMaxTextLength. Returns nil when `raw` is not a string or
/// nothing is left. `outTruncated` reports whether the cap applied.
NSString * _Nullable CDRSanitizedReleaseNoteText(id _Nullable raw, BOOL * _Nullable outTruncated);

/// One typed, plain-text release note. Display data only — never a security
/// input (spec.md §3.2).
@interface CDRReleaseNote : NSObject

@property (nonatomic, readonly) CDRReleaseNoteType type;
@property (nonatomic, readonly) NSString *text;

+ (instancetype)noteWithType:(CDRReleaseNoteType)type text:(NSString *)text;
- (instancetype)init NS_UNAVAILABLE;

@end

/// The notes of one type, in manifest order.
@interface CDRReleaseNoteGroup : NSObject

@property (nonatomic, readonly) CDRReleaseNoteType type;
@property (nonatomic, readonly) NSArray<CDRReleaseNote *> *notes;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Pure: notes → groups in the fixed render order, one group per type that is
/// present, manifest order preserved within a group.
NSArray<CDRReleaseNoteGroup *> *CDRGroupReleaseNotes(NSArray<CDRReleaseNote *> *notes);

/// The notes for one version: the advertised one, or a `history` entry.
@interface CDRRelease : NSObject

@property (nonatomic, readonly) NSString *version;
/// Local noon of the vendor-stated calendar day; nil when absent or invalid.
/// Display only — deferral never reads it (first_seen stays observation-based).
@property (nonatomic, readonly, nullable) NSDate *date;
/// In manifest order. Use `groups` to render.
@property (nonatomic, readonly) NSArray<CDRReleaseNote *> *notes;
/// Items dropped because their type is not one a manifest may carry (unknown,
/// or a forged "retracted"). Surfaced as a neutral one-liner, never rendered.
@property (nonatomic, readonly) NSUInteger undisplayableNoteCount;

@property (nonatomic, readonly) NSArray<CDRReleaseNoteGroup *> *groups;
@property (nonatomic, readonly) CDRReleaseNoteTypeSet typeSet;

- (instancetype)initWithVersion:(NSString *)version
                           date:(nullable NSDate *)date
                          notes:(NSArray<CDRReleaseNote *> *)notes
         undisplayableNoteCount:(NSUInteger)undisplayableNoteCount NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
