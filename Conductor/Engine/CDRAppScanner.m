//
//  CDRAppScanner.m
//  Conductor
//

#import "CDRAppScanner.h"
#import "CDRAppRegistration.h"

@implementation CDRAppScanner

- (NSArray<CDRAppRegistration *> *)scanDirectory:(NSURL *)directoryURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *entries = [fm contentsOfDirectoryAtURL:directoryURL
                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                       error:NULL];
    NSString *ownBundleID = [NSBundle mainBundle].bundleIdentifier;
    NSMutableArray<CDRAppRegistration *> *found = [NSMutableArray array];

    for (NSURL *entry in entries) {
        if (![entry.pathExtension isEqualToString:@"app"]) continue;
        NSURL *marker = [entry URLByAppendingPathComponent:[CDRAppRegistration conductorJSONRelativePath]];
        if (![fm fileExistsAtPath:marker.path]) continue;

        NSError *error = nil;
        CDRAppRegistration *reg = [CDRAppRegistration registrationForAppAtURL:entry error:&error];
        if (!reg) {
            NSLog(@"Conductor: skipping %@ (%@)", entry.lastPathComponent, error.localizedDescription);
            continue;
        }
        if ([reg.bundleID isEqualToString:ownBundleID]) continue;
        [found addObject:reg];
    }

    [found sortUsingComparator:^NSComparisonResult(CDRAppRegistration *a, CDRAppRegistration *b) {
        return [a.appURL.lastPathComponent localizedStandardCompare:b.appURL.lastPathComponent];
    }];
    return found;
}

- (NSArray<CDRAppRegistration *> *)scanApplicationsDirectory {
    return [self scanDirectory:[NSURL fileURLWithPath:@"/Applications" isDirectory:YES]];
}

@end
