//
//  CDRPrivilegedHelperManager.m
//  Conductor
//

#import "CDRPrivilegedHelperManager.h"
#import "CDRHelperProtocol.h"
#import "CDRErrors.h"
#import <ServiceManagement/ServiceManagement.h>

static NSString * const kHelperPlistName  = @"com.ranvel.Conductor.PrivilegedHelper.plist";
static NSString * const kHelperMachService = @"com.ranvel.Conductor.PrivilegedHelper";

@interface CDRPrivilegedHelperManager ()
@property (nonatomic, nullable) NSXPCConnection *connection;
@end

@implementation CDRPrivilegedHelperManager

+ (instancetype)sharedManager {
    static CDRPrivilegedHelperManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (BOOL)isHelperInstalled {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService daemonServiceWithPlistName:kHelperPlistName];
        return service.status == SMAppServiceStatusEnabled;
    }
    return NO;
}

- (BOOL)installHelperWithError:(NSError **)error {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService daemonServiceWithPlistName:kHelperPlistName];

        if (service.status == SMAppServiceStatusEnabled) return YES;

        if (service.status == SMAppServiceStatusRequiresApproval) {
            [SMAppService openSystemSettingsLoginItems];
            if (error) {
                *error = CDRError(CDRErrorPermissionDenied, nil, nil,
                    @{NSLocalizedDescriptionKey:
                        @"The privileged helper requires approval in "
                         "System Settings › Login Items."});
            }
            return NO;
        }

        NSError *regError = nil;
        if (![service registerAndReturnError:&regError]) {
            if (service.status == SMAppServiceStatusRequiresApproval) {
                [SMAppService openSystemSettingsLoginItems];
            }
            if (error) *error = regError;
            return NO;
        }
        return YES;
    }
    if (error) {
        *error = CDRError(CDRErrorPermissionDenied, nil, nil,
            @{NSLocalizedDescriptionKey:
                @"Privileged helper requires macOS 13 or later."});
    }
    return NO;
}

- (BOOL)uninstallHelperWithError:(NSError **)error {
    [self invalidateConnection];
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService daemonServiceWithPlistName:kHelperPlistName];
        return [service unregisterAndReturnError:error];
    }
    return YES;
}

- (void)swapBundleAtURL:(NSURL *)installedURL
        withStagedAtURL:(NSURL *)stagedURL
             completion:(void (^)(BOOL, NSURL * _Nullable, NSError * _Nullable))completion {
    NSXPCConnection *conn = [self getOrCreateConnection];
    if (!conn) {
        completion(NO, nil, CDRError(CDRErrorPermissionDenied, nil, nil,
            @{NSLocalizedDescriptionKey:
                @"Could not connect to the privileged helper."}));
        return;
    }

    id<CDRHelperProtocol> proxy =
        [conn remoteObjectProxyWithErrorHandler:^(NSError *xpcError) {
            completion(NO, nil, xpcError);
        }];

    [proxy swapBundleAtPath:installedURL.path
            withStagedAtPath:stagedURL.path
                   withReply:^(BOOL success, NSString *backupPath, NSString *errorMessage) {
        if (success) {
            NSURL *backupURL = backupPath ? [NSURL fileURLWithPath:backupPath] : nil;
            completion(YES, backupURL, nil);
        } else {
            completion(NO, nil, CDRError(CDRErrorSwapFailed, nil, nil,
                @{NSLocalizedDescriptionKey:
                    errorMessage ?: @"Privileged swap failed."}));
        }
    }];
}

#pragma mark - Connection

- (nullable NSXPCConnection *)getOrCreateConnection {
    if (self.connection) return self.connection;

    NSXPCConnection *conn =
        [[NSXPCConnection alloc] initWithMachServiceName:kHelperMachService
                                                 options:NSXPCConnectionPrivileged];
    conn.remoteObjectInterface =
        [NSXPCInterface interfaceWithProtocol:@protocol(CDRHelperProtocol)];

    __weak typeof(self) weakSelf = self;
    conn.invalidationHandler = ^{ weakSelf.connection = nil; };
    conn.interruptionHandler = ^{ weakSelf.connection = nil; };

    [conn resume];
    self.connection = conn;
    return conn;
}

- (void)invalidateConnection {
    [self.connection invalidate];
    self.connection = nil;
}

@end
