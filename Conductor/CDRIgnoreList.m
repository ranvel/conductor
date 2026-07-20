//
//  CDRIgnoreList.m
//  Conductor
//

#import "CDRIgnoreList.h"

NSString * const CDRIgnoredBundleIDsDefaultsKey = @"CDRIgnoredBundleIDs";

NSSet<NSString *> *CDRIgnoredBundleIDs(NSUserDefaults *defaults) {
    NSArray *stored = [defaults arrayForKey:CDRIgnoredBundleIDsDefaultsKey];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (id entry in stored) {
        if ([entry isKindOfClass:[NSString class]]) [set addObject:entry];
    }
    return set;
}

void CDRSetBundleIDIgnored(NSString *bundleID, BOOL ignored, NSUserDefaults *defaults) {
    NSMutableSet<NSString *> *set = [CDRIgnoredBundleIDs(defaults) mutableCopy];
    if (ignored) {
        [set addObject:bundleID];
    } else {
        [set removeObject:bundleID];
    }
    [defaults setObject:[set.allObjects sortedArrayUsingSelector:@selector(compare:)]
                 forKey:CDRIgnoredBundleIDsDefaultsKey];
}
