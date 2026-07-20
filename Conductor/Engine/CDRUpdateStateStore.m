//
//  CDRUpdateStateStore.m
//  Conductor
//

#import "CDRUpdateStateStore.h"

static NSString * const kStoreFileName = @"UpdateState.plist";
static NSString * const kFormatVersionKey = @"format_version";
static NSString * const kAppsKey = @"apps";
static const NSInteger kSupportedFormatVersion = 1;
/// M2 retention decision (roadmap.md "decide here"): 90 days.
static const NSTimeInterval kRetentionInterval = 90.0 * 24.0 * 60.0 * 60.0;

@interface CDRUpdateStateStore ()
@property (nonatomic) NSURL *fileURL;
@property (nonatomic) NSMutableDictionary<NSString *, CDRAppUpdateState *> *states;
@end

@implementation CDRUpdateStateStore

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL now:(NSDate *)now {
    self = [super init];
    if (self) {
        _fileURL = [directoryURL URLByAppendingPathComponent:kStoreFileName];
        _states = [NSMutableDictionary dictionary];
        [self loadWithRetentionAnchor:now];
    }
    return self;
}

+ (instancetype)defaultStore {
    NSURL *appSupport = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                               inDomain:NSUserDomainMask
                                                      appropriateForURL:nil
                                                                 create:YES
                                                                  error:NULL];
    NSURL *dir = [appSupport URLByAppendingPathComponent:@"Conductor" isDirectory:YES];
    return [[self alloc] initWithDirectoryURL:dir now:[NSDate date]];
}

#pragma mark - Load / save

- (void)loadWithRetentionAnchor:(NSDate *)now {
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
    if (!data) return;

    id root = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListImmutable
                                                         format:NULL
                                                          error:NULL];
    if (![root isKindOfClass:[NSDictionary class]]) return;

    // An unknown format version means a newer Conductor wrote this file —
    // start fresh rather than guess at its semantics.
    NSNumber *format = root[kFormatVersionKey];
    if (![format isKindOfClass:[NSNumber class]] || format.integerValue != kSupportedFormatVersion) return;

    id apps = root[kAppsKey];
    if (![apps isKindOfClass:[NSDictionary class]]) return;

    [apps enumerateKeysAndObjectsUsingBlock:^(id bundleID, id entry, BOOL *stop) {
        if (![bundleID isKindOfClass:[NSString class]]) return;
        CDRAppUpdateState *state = [CDRAppUpdateState stateWithBundleID:bundleID
                                                      propertyListEntry:entry];
        if (!state) return;
        if ([now timeIntervalSinceDate:state.updatedAt] > kRetentionInterval) return;
        self.states[bundleID] = state;
    }];
}

- (void)save {
    NSMutableDictionary *apps = [NSMutableDictionary dictionary];
    [self.states enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, CDRAppUpdateState *state, BOOL *stop) {
        apps[bundleID] = [state propertyListEntry];
    }];
    NSDictionary *root = @{ kFormatVersionKey: @(kSupportedFormatVersion), kAppsKey: apps };

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:NULL];
    if (!data) return;
    [[NSFileManager defaultManager] createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    [data writeToURL:self.fileURL atomically:YES];
}

#pragma mark - Access

- (CDRAppUpdateState *)stateForBundleID:(NSString *)bundleID {
    return self.states[bundleID];
}

- (void)putState:(CDRAppUpdateState *)state {
    self.states[state.bundleID] = state;
    [self save];
}

- (void)noteNotifiedVersion:(NSString *)version
                      build:(NSString *)build
                forBundleID:(NSString *)bundleID
                         at:(NSDate *)date {
    CDRAppUpdateState *state = self.states[bundleID]
        ?: [CDRAppUpdateState emptyStateWithBundleID:bundleID at:date];
    [self putState:[state stateByNotingNotifiedVersion:version build:build at:date]];
}

- (void)clearNotifiedVersionForBundleID:(NSString *)bundleID at:(NSDate *)date {
    CDRAppUpdateState *state = self.states[bundleID];
    if (!state) return;
    [self putState:[state stateByClearingNotifiedAt:date]];
}

@end
