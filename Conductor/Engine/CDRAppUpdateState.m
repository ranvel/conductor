//
//  CDRAppUpdateState.m
//  Conductor
//

#import "CDRAppUpdateState.h"

static NSString * const kLastSeenVersionKey = @"last_seen_version";
static NSString * const kLastSeenBuildKey = @"last_seen_build";
static NSString * const kFirstSeenKey = @"first_seen";
static NSString * const kLastNotifiedVersionKey = @"last_notified_version";
static NSString * const kLastNotifiedBuildKey = @"last_notified_build";
static NSString * const kNotifiedAtKey = @"notified_at";
static NSString * const kUpdatedAtKey = @"updated_at";
static NSString * const kSkippedVersionKey = @"skipped_version";

@implementation CDRAppUpdateState

/// `skippedVersion` rides outside the designated initializer (whose
/// signature is part of the M2 contract): every derived copy passes through
/// here to say whether the skip survives.
- (instancetype)carryingSkippedVersion:(nullable NSString *)skippedVersion {
    _skippedVersion = [skippedVersion copy];
    return self;
}

- (instancetype)initWithBundleID:(NSString *)bundleID
                 lastSeenVersion:(NSString *)lastSeenVersion
                   lastSeenBuild:(NSString *)lastSeenBuild
              firstSeenByVersion:(NSDictionary<NSString *, NSDate *> *)firstSeenByVersion
             lastNotifiedVersion:(NSString *)lastNotifiedVersion
               lastNotifiedBuild:(NSString *)lastNotifiedBuild
                      notifiedAt:(NSDate *)notifiedAt
                       updatedAt:(NSDate *)updatedAt {
    self = [super init];
    if (self) {
        _bundleID = [bundleID copy];
        _lastSeenVersion = [lastSeenVersion copy];
        _lastSeenBuild = [lastSeenBuild copy];
        _firstSeenByVersion = [firstSeenByVersion copy] ?: @{};
        _lastNotifiedVersion = [lastNotifiedVersion copy];
        _lastNotifiedBuild = [lastNotifiedBuild copy];
        _notifiedAt = notifiedAt;
        _updatedAt = updatedAt;
    }
    return self;
}

+ (instancetype)emptyStateWithBundleID:(NSString *)bundleID at:(NSDate *)date {
    return [[self alloc] initWithBundleID:bundleID
                          lastSeenVersion:nil
                            lastSeenBuild:nil
                       firstSeenByVersion:@{}
                      lastNotifiedVersion:nil
                        lastNotifiedBuild:nil
                               notifiedAt:nil
                                updatedAt:date];
}

#pragma mark - Derived copies

- (NSDictionary<NSString *, NSDate *> *)prunedFirstSeenKeeping:(NSDictionary<NSString *, NSDate *> *)firstSeen
                                                   seenVersion:(NSString *)seenVersion
                                               notifiedVersion:(NSString *)notifiedVersion {
    NSMutableDictionary<NSString *, NSDate *> *pruned = [NSMutableDictionary dictionary];
    if (seenVersion && firstSeen[seenVersion]) pruned[seenVersion] = firstSeen[seenVersion];
    if (notifiedVersion && firstSeen[notifiedVersion]) pruned[notifiedVersion] = firstSeen[notifiedVersion];
    return pruned;
}

- (instancetype)stateBySeeingVersion:(NSString *)version build:(NSString *)build at:(NSDate *)date {
    NSMutableDictionary<NSString *, NSDate *> *firstSeen = [self.firstSeenByVersion mutableCopy];
    if (!firstSeen[version]) firstSeen[version] = date;
    // A skip is about exactly one version. Once the developer advertises a
    // different one, there is nothing left to skip.
    NSString *skipped = [self.skippedVersion isEqualToString:version] ? self.skippedVersion : nil;
    return [[[CDRAppUpdateState alloc] initWithBundleID:self.bundleID
                                        lastSeenVersion:version
                                          lastSeenBuild:build
                                     firstSeenByVersion:[self prunedFirstSeenKeeping:firstSeen
                                                                         seenVersion:version
                                                                     notifiedVersion:self.lastNotifiedVersion]
                                    lastNotifiedVersion:self.lastNotifiedVersion
                                      lastNotifiedBuild:self.lastNotifiedBuild
                                             notifiedAt:self.notifiedAt
                                              updatedAt:date] carryingSkippedVersion:skipped];
}

- (instancetype)copyUpdatedAt:(NSDate *)date skippedVersion:(nullable NSString *)skippedVersion {
    return [[[CDRAppUpdateState alloc] initWithBundleID:self.bundleID
                                        lastSeenVersion:self.lastSeenVersion
                                          lastSeenBuild:self.lastSeenBuild
                                     firstSeenByVersion:self.firstSeenByVersion
                                    lastNotifiedVersion:self.lastNotifiedVersion
                                      lastNotifiedBuild:self.lastNotifiedBuild
                                             notifiedAt:self.notifiedAt
                                              updatedAt:date] carryingSkippedVersion:skippedVersion];
}

- (instancetype)stateBySkippingVersion:(NSString *)version at:(NSDate *)date {
    return [self copyUpdatedAt:date skippedVersion:version];
}

- (instancetype)stateByClearingSkippedVersionAt:(NSDate *)date {
    return [self copyUpdatedAt:date skippedVersion:nil];
}

- (instancetype)stateByNotingNotifiedVersion:(NSString *)version build:(NSString *)build at:(NSDate *)date {
    return [[[CDRAppUpdateState alloc] initWithBundleID:self.bundleID
                                       lastSeenVersion:self.lastSeenVersion
                                         lastSeenBuild:self.lastSeenBuild
                                    firstSeenByVersion:[self prunedFirstSeenKeeping:self.firstSeenByVersion
                                                                        seenVersion:self.lastSeenVersion
                                                                    notifiedVersion:version]
                                   lastNotifiedVersion:version
                                     lastNotifiedBuild:build
                                            notifiedAt:date
                                             updatedAt:date] carryingSkippedVersion:self.skippedVersion];
}

- (instancetype)stateByClearingNotifiedAt:(NSDate *)date {
    return [[[CDRAppUpdateState alloc] initWithBundleID:self.bundleID
                                       lastSeenVersion:self.lastSeenVersion
                                         lastSeenBuild:self.lastSeenBuild
                                    firstSeenByVersion:[self prunedFirstSeenKeeping:self.firstSeenByVersion
                                                                        seenVersion:self.lastSeenVersion
                                                                    notifiedVersion:nil]
                                   lastNotifiedVersion:nil
                                     lastNotifiedBuild:nil
                                            notifiedAt:nil
                                             updatedAt:date] carryingSkippedVersion:self.skippedVersion];
}

#pragma mark - Plist round-trip

static NSString *StringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

static NSDate *DateOrNil(id value) {
    return [value isKindOfClass:[NSDate class]] ? value : nil;
}

+ (nullable instancetype)stateWithBundleID:(NSString *)bundleID propertyListEntry:(NSDictionary *)entry {
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    NSDate *updatedAt = DateOrNil(entry[kUpdatedAtKey]);
    if (!updatedAt) return nil;

    NSMutableDictionary<NSString *, NSDate *> *firstSeen = [NSMutableDictionary dictionary];
    id rawFirstSeen = entry[kFirstSeenKey];
    if ([rawFirstSeen isKindOfClass:[NSDictionary class]]) {
        [rawFirstSeen enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSDate class]]) {
                firstSeen[key] = value;
            }
        }];
    }

    return [[[self alloc] initWithBundleID:bundleID
                           lastSeenVersion:StringOrNil(entry[kLastSeenVersionKey])
                             lastSeenBuild:StringOrNil(entry[kLastSeenBuildKey])
                        firstSeenByVersion:firstSeen
                       lastNotifiedVersion:StringOrNil(entry[kLastNotifiedVersionKey])
                         lastNotifiedBuild:StringOrNil(entry[kLastNotifiedBuildKey])
                                notifiedAt:DateOrNil(entry[kNotifiedAtKey])
                                 updatedAt:updatedAt]
            carryingSkippedVersion:StringOrNil(entry[kSkippedVersionKey])];
}

- (NSDictionary *)propertyListEntry {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    if (self.lastSeenVersion) entry[kLastSeenVersionKey] = self.lastSeenVersion;
    if (self.lastSeenBuild) entry[kLastSeenBuildKey] = self.lastSeenBuild;
    entry[kFirstSeenKey] = self.firstSeenByVersion;
    if (self.lastNotifiedVersion) entry[kLastNotifiedVersionKey] = self.lastNotifiedVersion;
    if (self.lastNotifiedBuild) entry[kLastNotifiedBuildKey] = self.lastNotifiedBuild;
    if (self.notifiedAt) entry[kNotifiedAtKey] = self.notifiedAt;
    entry[kUpdatedAtKey] = self.updatedAt;
    if (self.skippedVersion) entry[kSkippedVersionKey] = self.skippedVersion;
    return entry;
}

@end
