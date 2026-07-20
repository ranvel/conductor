//
//  CDRAppUpdateState.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One app's update memory (the deferral.md state model, which amends
/// retraction.md): what Conductor has *observed* (last_seen + first_seen per
/// version — the soak clock) vs what it has *surfaced to the user*
/// (last_notified + notified_at — what retraction loudness is owed for).
///
/// Immutable snapshot; derive changed copies via the stateBy… methods and
/// persist through CDRUpdateStateStore. Every timestamp is caller-supplied so
/// the whole model is testable with fixed dates.
@interface CDRAppUpdateState : NSObject

@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly, nullable) NSString *lastSeenVersion;
@property (nonatomic, readonly, nullable) NSString *lastSeenBuild;
/// first_seen is when *this instance* first observed the version in a
/// manifest — never a vendor-supplied date, which could be backdated to
/// defeat the soak (deferral.md).
@property (nonatomic, readonly) NSDictionary<NSString *, NSDate *> *firstSeenByVersion;
@property (nonatomic, readonly, nullable) NSString *lastNotifiedVersion;
@property (nonatomic, readonly, nullable) NSString *lastNotifiedBuild;
@property (nonatomic, readonly, nullable) NSDate *notifiedAt;
/// Refreshed on every mutation; the store's retention TTL keys on it.
@property (nonatomic, readonly) NSDate *updatedAt;

- (instancetype)initWithBundleID:(NSString *)bundleID
                 lastSeenVersion:(nullable NSString *)lastSeenVersion
                   lastSeenBuild:(nullable NSString *)lastSeenBuild
              firstSeenByVersion:(NSDictionary<NSString *, NSDate *> *)firstSeenByVersion
             lastNotifiedVersion:(nullable NSString *)lastNotifiedVersion
               lastNotifiedBuild:(nullable NSString *)lastNotifiedBuild
                      notifiedAt:(nullable NSDate *)notifiedAt
                       updatedAt:(NSDate *)updatedAt NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Fresh empty record for an app never seen before.
+ (instancetype)emptyStateWithBundleID:(NSString *)bundleID at:(NSDate *)date;

/// Ingestion (deferral.md: "ingested immediately but hidden"): sets last_seen,
/// records first_seen for the version only if absent (set-once — re-observing
/// must not restart the soak clock), and prunes first_seen to at most
/// {this version, last_notified_version} so superseded soaks (vX+1 under a new
/// vX+2) drop out by construction.
- (instancetype)stateBySeeingVersion:(NSString *)version
                               build:(nullable NSString *)build
                                  at:(NSDate *)date;

/// Marks a version surfaced to the user — normal notify, urgency notify, or
/// break-through install consent. From here on retraction loudness applies.
- (instancetype)stateByNotingNotifiedVersion:(NSString *)version
                                       build:(nullable NSString *)build
                                          at:(NSDate *)date;

/// Retraction State A resolution: the pending promise is cleared; loudness for
/// that version is one-time-ever because this removes the memory that owed it.
- (instancetype)stateByClearingNotifiedAt:(NSDate *)date;

/// Plist round-trip. Returns nil when the entry is garbage (wrong types).
+ (nullable instancetype)stateWithBundleID:(NSString *)bundleID
                         propertyListEntry:(NSDictionary *)entry;
- (NSDictionary *)propertyListEntry;

@end

NS_ASSUME_NONNULL_END
