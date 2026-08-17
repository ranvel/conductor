//
//  CDRArtifactStager.m
//  Conductor
//

#import "CDRArtifactStager.h"
#import "CDRErrors.h"

@implementation CDRArtifactStager

+ (NSURL *)stagingRootNearDestination:(NSURL *)destinationURL {
    // The destination is either the app bundle being replaced or a containing
    // folder like /Applications. hasDirectoryPath cannot tell those apart: an
    // .app bundle IS a directory, and a file URL carries the directory hint
    // whenever its path exists as one — which routed staging *inside* the very
    // bundle the swap replaces, and renamex_np refuses to swap a directory
    // with its own descendant (EINVAL). Discriminate by extension instead.
    BOOL isBundle = [destinationURL.pathExtension isEqualToString:@"app"];
    NSURL *parent = isBundle ? destinationURL.URLByDeletingLastPathComponent : destinationURL;
    return [parent URLByAppendingPathComponent:@".conductor-staging" isDirectory:YES];
}

- (nullable NSURL *)createStagingDirectoryForBundleID:(NSString *)bundleID
                                      nearDestination:(NSURL *)destinationURL
                                                error:(NSError **)error {
    NSURL *staging = [[CDRArtifactStager stagingRootNearDestination:destinationURL]
                      URLByAppendingPathComponent:bundleID isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *fsError = nil;
    // Start from a clean slate: stale staging from a crashed run is garbage.
    [fm removeItemAtURL:staging error:NULL];
    if (![fm createDirectoryAtURL:staging withIntermediateDirectories:YES attributes:nil error:&fsError]) {
        if (error) *error = CDRError(CDRErrorStagingCreateFailed, bundleID, fsError, nil);
        return nil;
    }
    return staging;
}

- (void)removeStagingDirectoryForBundleID:(NSString *)bundleID
                          nearDestination:(NSURL *)destinationURL {
    NSURL *root = [CDRArtifactStager stagingRootNearDestination:destinationURL];
    NSURL *staging = [root URLByAppendingPathComponent:bundleID isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:staging error:NULL];
    // Remove the root too if it's now empty (best effort; rmdir semantics).
    rmdir(root.fileSystemRepresentation);
}

- (nullable NSURL *)extractArtifactAtURL:(NSURL *)artifactURL
                      toStagingDirectory:(NSURL *)stagingURL
                                bundleID:(nullable NSString *)bundleID
                                   error:(NSError **)error {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:artifactURL.path];
    NSData *magic = [fh readDataOfLength:4];
    [fh closeFile];

    static const char zipMagic[] = {'P', 'K', 0x03, 0x04};
    BOOL isZip = magic.length == 4 && memcmp(magic.bytes, zipMagic, 4) == 0;

    NSURL *extractDir = [stagingURL URLByAppendingPathComponent:@"extracted" isDirectory:YES];
    NSError *fsError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:extractDir
                                  withIntermediateDirectories:YES attributes:nil error:&fsError]) {
        if (error) *error = CDRError(CDRErrorStagingCreateFailed, bundleID, fsError, nil);
        return nil;
    }

    BOOL ok = isZip ? [self extractZip:artifactURL to:extractDir bundleID:bundleID error:error]
                    : [self extractDMG:artifactURL to:extractDir bundleID:bundleID error:error];
    if (!ok) return nil;

    return [self findSingleAppIn:extractDir bundleID:bundleID error:error];
}

#pragma mark - Formats

- (BOOL)extractZip:(NSURL *)artifact to:(NSURL *)dir bundleID:(NSString *)bundleID error:(NSError **)error {
    // ditto -xk preserves xattrs (including quarantine) and resource forks.
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    task.arguments = @[@"-xk", artifact.path, dir.path];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = CDRError(CDRErrorExtractFailed, bundleID, launchError, nil);
        return NO;
    }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        if (error) *error = CDRError(CDRErrorExtractFailed, bundleID, nil, nil);
        return NO;
    }
    return YES;
}

- (BOOL)extractDMG:(NSURL *)artifact to:(NSURL *)dir bundleID:(NSString *)bundleID error:(NSError **)error {
    NSTask *attach = [[NSTask alloc] init];
    attach.executableURL = [NSURL fileURLWithPath:@"/usr/bin/hdiutil"];
    attach.arguments = @[@"attach", artifact.path, @"-nobrowse", @"-readonly",
                         @"-mountrandom", NSTemporaryDirectory(), @"-plist"];
    NSPipe *stdoutPipe = [NSPipe pipe];
    attach.standardOutput = stdoutPipe;
    attach.standardError = [NSPipe pipe];

    NSError *launchError = nil;
    if (![attach launchAndReturnError:&launchError]) {
        if (error) *error = CDRError(CDRErrorAttachFailed, bundleID, launchError, nil);
        return NO;
    }
    NSData *plistData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    [attach waitUntilExit];
    if (attach.terminationStatus != 0) {
        if (error) *error = CDRError(CDRErrorAttachFailed, bundleID, nil, nil);
        return NO;
    }

    NSString *mountPoint = nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                    options:0 format:NULL error:NULL];
    for (NSDictionary *entity in plist[@"system-entities"]) {
        NSString *mp = entity[@"mount-point"];
        if ([mp isKindOfClass:[NSString class]] && mp.length > 0) { mountPoint = mp; break; }
    }
    if (!mountPoint) {
        if (error) *error = CDRError(CDRErrorAttachFailed, bundleID, nil, nil);
        return NO;
    }

    // Copy the single .app off the image, preserving xattrs, then detach —
    // detach must happen on every path from here.
    BOOL copied = NO;
    NSError *copyError = nil;
    NSArray<NSURL *> *entries = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:[NSURL fileURLWithPath:mountPoint isDirectory:YES]
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:NULL];
    for (NSURL *entry in entries) {
        if (![entry.pathExtension isEqualToString:@"app"]) continue;
        // ditto (not NSFileManager copy) to guarantee xattr preservation.
        NSTask *copy = [[NSTask alloc] init];
        copy.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
        copy.arguments = @[entry.path, [dir URLByAppendingPathComponent:entry.lastPathComponent].path];
        copy.standardOutput = [NSPipe pipe];
        copy.standardError = [NSPipe pipe];
        if ([copy launchAndReturnError:&copyError]) {
            [copy waitUntilExit];
            copied = (copy.terminationStatus == 0);
        }
        break;
    }

    NSTask *detach = [[NSTask alloc] init];
    detach.executableURL = [NSURL fileURLWithPath:@"/usr/bin/hdiutil"];
    detach.arguments = @[@"detach", mountPoint, @"-force"];
    detach.standardOutput = [NSPipe pipe];
    detach.standardError = [NSPipe pipe];
    if ([detach launchAndReturnError:NULL]) [detach waitUntilExit];

    if (!copied) {
        if (error) *error = CDRError(CDRErrorNoAppInArtifact, bundleID, copyError, nil);
        return NO;
    }
    return YES;
}

#pragma mark - Locate

- (nullable NSURL *)findSingleAppIn:(NSURL *)dir bundleID:(NSString *)bundleID error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    // Zip artifacts sometimes wrap the .app in one directory level; look two deep.
    NSMutableArray<NSURL *> *apps = [NSMutableArray array];
    NSArray<NSURL *> *level1 = [fm contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil
                                                    options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *entry in level1) {
        if ([entry.pathExtension isEqualToString:@"app"]) {
            [apps addObject:entry];
        } else {
            NSNumber *isDir = nil;
            [entry getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
            if (isDir.boolValue) {
                NSArray<NSURL *> *level2 = [fm contentsOfDirectoryAtURL:entry includingPropertiesForKeys:nil
                                                                options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
                for (NSURL *sub in level2) {
                    if ([sub.pathExtension isEqualToString:@"app"]) [apps addObject:sub];
                }
            }
        }
    }
    if (apps.count != 1) {
        if (error) *error = CDRError(CDRErrorNoAppInArtifact, bundleID, nil, nil);
        return nil;
    }
    return apps.firstObject;
}

@end
