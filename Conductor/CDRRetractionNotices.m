//
//  CDRRetractionNotices.m
//  Conductor
//

#import "CDRRetractionNotices.h"

NSString * const CDRRetractionNoticesDefaultsKey = @"CDRRetractionNotices";

@implementation CDRRetractionNotice

+ (instancetype)noticeWithVersion:(NSString *)version advertisedAt:(NSDate *)advertisedAt pulledAt:(NSDate *)pulledAt {
    CDRRetractionNotice *notice = [[CDRRetractionNotice alloc] init];
    notice->_version = [version copy];
    notice->_advertisedAt = advertisedAt;
    notice->_pulledAt = pulledAt;
    return notice;
}

@end

CDRRetractionNotice *CDRRetractionNoticeForBundleID(NSString *bundleID, NSUserDefaults *defaults) {
    id all = [defaults objectForKey:CDRRetractionNoticesDefaultsKey];
    id entry = [all isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)all)[bundleID] : nil;
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    NSString *version = entry[@"version"];
    NSDate *pulledAt = entry[@"pulled_at"];
    NSDate *advertisedAt = entry[@"advertised_at"];
    if (![version isKindOfClass:[NSString class]] || version.length == 0) return nil;
    if (![pulledAt isKindOfClass:[NSDate class]]) return nil;
    return [CDRRetractionNotice noticeWithVersion:version
                                     advertisedAt:[advertisedAt isKindOfClass:[NSDate class]] ? advertisedAt : nil
                                         pulledAt:pulledAt];
}

void CDRSetRetractionNotice(CDRRetractionNotice *notice, NSString *bundleID, NSUserDefaults *defaults) {
    id stored = [defaults objectForKey:CDRRetractionNoticesDefaultsKey];
    NSMutableDictionary *all = [stored isKindOfClass:[NSDictionary class]]
        ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (notice) {
        NSMutableDictionary *entry = [@{@"version": notice.version, @"pulled_at": notice.pulledAt} mutableCopy];
        if (notice.advertisedAt) entry[@"advertised_at"] = notice.advertisedAt;
        all[bundleID] = entry;
    } else {
        [all removeObjectForKey:bundleID];
    }
    if (all.count == 0) [defaults removeObjectForKey:CDRRetractionNoticesDefaultsKey];
    else [defaults setObject:all forKey:CDRRetractionNoticesDefaultsKey];
}
