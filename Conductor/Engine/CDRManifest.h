//
//  CDRManifest.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRReleaseNote.h"

NS_ASSUME_NONNULL_BEGIN

/// Closed urgency vocabulary (deferral.md). The manifest carries only a token;
/// Conductor renders its own fixed copy. Unknown tokens map to None.
typedef NS_ENUM(NSInteger, CDRUrgency) {
    CDRUrgencyNone = 0,
    CDRUrgencySystemRisk,
    CDRUrgencyDataLoss,
    CDRUrgencyDataExfiltration,
};

/// Conductor reads at most this many `history` entries, and at most
/// CDRManifestMaxNotesPerRelease notes per release; the rest are ignored.
extern const NSUInteger CDRManifestMaxHistoryEntries;
extern const NSUInteger CDRManifestMaxNotesPerRelease;

/// The vendor-served update manifest. Unauthenticated by design — nothing in
/// it is a security input except the artifact URL, whose payload is verified
/// independently (Team ID pinning, replace-flow.md §3).
@interface CDRManifest : NSObject

@property (nonatomic, readonly) NSInteger formatVersion;      // conductor_manifest
@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly) NSString *version;            // advisory / display
@property (nonatomic, readonly, nullable) NSString *build;
@property (nonatomic, readonly) NSURL *artifactURL;
@property (nonatomic, readonly, nullable) NSString *sha256;   // integrity hint, not a security boundary
@property (nonatomic, readonly) CDRUrgency urgency;
@property (nonatomic, readonly, nullable) NSURL *changelogURL;
@property (nonatomic, readonly, nullable) NSString *minSystemVersion;

#pragma mark Release notes (spec.md §3.5) — display data, never a security input

/// The advertised version's notes (`notes` + `released`). Never nil: a
/// manifest without notes yields a release with an empty `notes` array.
@property (nonatomic, readonly) CDRRelease *advertisedRelease;
/// `history` as served, validated, at most CDRManifestMaxHistoryEntries.
/// Unfiltered — use -releasesNewerThanVersion: to render.
@property (nonatomic, readonly) NSArray<CDRRelease *> *history;
/// `size`: the artifact's size in bytes, for display only.
@property (nonatomic, readonly, nullable) NSNumber *artifactSize;
/// Human-readable notes about anything dropped or ignored while parsing the
/// optional display fields. The parser stays pure; callers log these.
@property (nonatomic, readonly) NSArray<NSString *> *parseWarnings;

/// What an update from `installedVersion` contains: the advertised release
/// first, then every `history` entry strictly newer than the installed
/// version and strictly older than the advertised one, newest first. Empty
/// when the advertised version is not newer than the installed one.
- (NSArray<CDRRelease *> *)releasesNewerThanVersion:(NSString *)installedVersion;

+ (nullable instancetype)manifestWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
