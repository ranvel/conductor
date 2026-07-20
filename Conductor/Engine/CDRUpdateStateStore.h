//
//  CDRUpdateStateStore.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRAppUpdateState.h"

NS_ASSUME_NONNULL_BEGIN

/// Persists all per-app update memory in ONE plist under Application Support
/// (the open question both deferral.md and retraction.md leave to
/// implementation, resolved per roadmap.md: one file for both). The file stays
/// tiny by construction — first_seen is pruned to at most two versions per app
/// on each ingest, and whole records untouched for 90 days are dropped at load
/// (M2 retention decision; any check refreshes updated_at, so records for
/// managed apps never expire — only deleted/unmanaged apps age out).
///
/// A corrupt, missing, or future-format file yields an empty store: this is
/// probabilistic memory, not a security input — losing it degrades to M1
/// behavior (everything surfaces immediately), never to a wrong decision.
@interface CDRUpdateStateStore : NSObject

/// Designated. The store file is <directoryURL>/UpdateState.plist; the
/// directory is created on first write. `now` anchors the retention sweep —
/// tests inject a temp directory and a fixed date.
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL now:(NSDate *)now NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// ~/Library/Application Support/Conductor/, retention anchored at the
/// current date.
+ (instancetype)defaultStore;

- (nullable CDRAppUpdateState *)stateForBundleID:(NSString *)bundleID;

/// Writes a record verbatim (the policy's stateAfterCheck) and rewrites the
/// file atomically.
- (void)putState:(CDRAppUpdateState *)state;

/// Marks a version surfaced outside the normal check path — break-through
/// install consent (deferral.md: installing a soaking version marks it
/// notified, so retraction loudness applies to it like any surfaced update).
- (void)noteNotifiedVersion:(NSString *)version
                      build:(nullable NSString *)build
                forBundleID:(NSString *)bundleID
                         at:(NSDate *)date;

/// Retraction State A resolution from outside the normal check path — the
/// last-moment re-check refusal (retraction.md). No-op for unknown apps.
- (void)clearNotifiedVersionForBundleID:(NSString *)bundleID at:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
