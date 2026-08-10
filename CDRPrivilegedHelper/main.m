//
//  main.m
//  CDRPrivilegedHelper
//
//  Created by ranvel on 8/9/26.
//
//  Root XPC daemon. Single job: perform the atomic bundle swap that the
//  unprivileged CDRAtomicSwapper cannot when /Applications denies it (EPERM).
//
//  Trust model: this process runs as root, so the ONLY thing standing between
//  a caller and a root-level filesystem mutation is -shouldAcceptNewConnection:.
//  Every connection is validated against the connecting process's AUDIT TOKEN
//  (never its PID — PIDs are recycled, which is the classic XPC reuse race) and
//  pinned to BOTH the code-signing identifier AND the team. Identifier + team,
//  not team alone: a sibling app under the same Developer ID (muwav) must not be
//  able to drive this. See -[CDRHelperListener isValidClient:] and
//  +[CDRCodeSignature validateConnection:pinnedTeamID:pinnedIdentifier:error:].
//

#import <Foundation/Foundation.h>
#import "CDRHelperProtocol.h"
#import "CDRCodeSignature.h"

// MUST stay in sync with CDRPrivilegedHelperManager's kHelperMachService and the
// LaunchDaemon plist's MachServices key. If these three ever disagree, the
// manager connects to a listener that isn't there and the swap silently hangs.
static NSString * const kHelperMachService = @"com.ranvel.Conductor.PrivilegedHelper";

// The one and only client permitted to drive a root swap.
static NSString * const kPinnedIdentifier = @"com.ranvel.Conductor";
static NSString * const kPinnedTeamID     = @"F252L9GUBW";

#pragma mark - Swap executor (the exported object)

@interface CDRHelperSwap : NSObject <CDRHelperProtocol>
@end

@implementation CDRHelperSwap

- (void)swapBundleAtPath:(NSString *)installedPath
        withStagedAtPath:(NSString *)stagedPath
               withReply:(void (^)(BOOL, NSString * _Nullable, NSString * _Nullable))reply {

    // Defense in depth: the peer is already validated, but this is root code
    // operating on client-supplied paths. Reject anything that isn't a plain,
    // absolute path to an existing directory before we touch the filesystem.
    NSFileManager *fm = [NSFileManager defaultManager];
    if (installedPath.length == 0 || stagedPath.length == 0 ||
        !installedPath.isAbsolutePath || !stagedPath.isAbsolutePath) {
        reply(NO, nil, @"Installed and staged paths must both be absolute.");
        return;
    }

    BOOL stagedIsDir = NO, installedIsDir = NO;
    if (![fm fileExistsAtPath:stagedPath isDirectory:&stagedIsDir] || !stagedIsDir) {
        reply(NO, nil, @"Staged bundle does not exist.");
        return;
    }
    if (![fm fileExistsAtPath:installedPath isDirectory:&installedIsDir] || !installedIsDir) {
        reply(NO, nil, @"Installed bundle does not exist.");
        return;
    }

    NSURL *installedURL = [NSURL fileURLWithPath:installedPath];
    NSURL *stagedURL    = [NSURL fileURLWithPath:stagedPath];

    // Same backup convention as CDRAtomicSwapper: a sibling of the original,
    // named "<bundle>.conductor-displaced-<UUID>", left in place (WithoutDeleting)
    // for the app side to trash after it confirms the swap.
    NSString *backupName = [NSString stringWithFormat:@"%@.conductor-displaced-%@",
                            installedURL.lastPathComponent, NSUUID.UUID.UUIDString];

    NSURL *resultingURL = nil;
    NSError *replaceError = nil;
    BOOL ok = [fm replaceItemAtURL:installedURL
                     withItemAtURL:stagedURL
                    backupItemName:backupName
                           options:(NSFileManagerItemReplacementUsingNewMetadataOnly |
                                    NSFileManagerItemReplacementWithoutDeletingBackupItem)
                  resultingItemURL:&resultingURL
                             error:&replaceError];

    if (!ok) {
        reply(NO, nil, replaceError.localizedDescription ?: @"replaceItemAtURL failed.");
        return;
    }

    NSURL *backupURL = [installedURL.URLByDeletingLastPathComponent
                        URLByAppendingPathComponent:backupName];
    NSString *backupPath = [fm fileExistsAtPath:backupURL.path] ? backupURL.path : nil;
    reply(YES, backupPath, nil);
}

@end

#pragma mark - Listener delegate (the gate)

@interface CDRHelperListener : NSObject <NSXPCListenerDelegate>
@end

@implementation CDRHelperListener

- (BOOL)listener:(NSXPCListener *)listener
        shouldAcceptNewConnection:(NSXPCConnection *)newConnection {

    // Validate BEFORE exporting anything. A connection we don't trust never
    // receives an interface, an exported object, or a -resume.
    if (![self isValidClient:newConnection]) {
        return NO;
    }

    newConnection.exportedInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(CDRHelperProtocol)];
    newConnection.exportedObject = [CDRHelperSwap new];
    [newConnection resume];
    return YES;
}

- (BOOL)isValidClient:(NSXPCConnection *)connection {
    NSError *error = nil;
    BOOL valid = [CDRCodeSignature validateConnection:connection
                                         pinnedTeamID:kPinnedTeamID
                                     pinnedIdentifier:kPinnedIdentifier
                                                error:&error];
    if (!valid) {
        // Log the reason only — never any client-supplied data.
        NSLog(@"[CDRPrivilegedHelper] rejected connection: %@",
              error.localizedDescription ?: @"unknown");
    }
    return valid;
}

@end

#pragma mark - Entry point

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        CDRHelperListener *delegate = [CDRHelperListener new];

        NSXPCListener *listener =
            [[NSXPCListener alloc] initWithMachServiceName:kHelperMachService];
        listener.delegate = delegate;
        [listener resume];

        // Daemon: park here and service events forever. launchd owns our
        // lifecycle (on-demand via MachServices), so control never returns.
        dispatch_main();
    }
    return EXIT_SUCCESS; // unreachable
}