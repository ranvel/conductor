//
//  CDRDevModeSession.m
//  Conductor
//

#import "CDRDevModeSession.h"
#import "CDRErrors.h"

NSString * const CDRDevModeArgument = @"--dev-mode";

@implementation CDRDevModeSession

+ (nullable instancetype)sessionFromArguments:(NSArray<NSString *> *)arguments
                                        error:(NSError **)error {
    NSString *bundleID = nil;
    // Skip argv[0].
    NSUInteger i = arguments.count > 0 ? 1 : 0;
    for (; i < arguments.count; i++) {
        if (![arguments[i] isEqualToString:CDRDevModeArgument]) continue;
        if (bundleID != nil || i + 1 >= arguments.count ||
            [arguments[i + 1] hasPrefix:@"-"]) {
            // Repeated flag, or flag without an operand.
            if (error) {
                *error = [NSError errorWithDomain:CDRErrorDomain
                                             code:CDRErrorConductorJSONMalformed
                                         userInfo:@{NSLocalizedDescriptionKey:
                    @"--dev-mode requires exactly one bundle identifier."}];
            }
            return nil;
        }
        bundleID = arguments[i + 1];
        i++;
    }

    CDRDevModeSession *session = [[CDRDevModeSession alloc] init];
    session->_devModeEnabled = (bundleID != nil);
    session->_devModeBundleID = [bundleID copy];
    return session;
}

- (BOOL)isBundleVisible:(NSString *)bundleID {
    if (!self.devModeEnabled) return YES;
    return [bundleID isEqualToString:self.devModeBundleID];
}

- (BOOL)allowsURL:(NSURL *)url forBundleID:(NSString *)bundleID {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"]) return YES;
    if (![scheme isEqualToString:@"http"]) return NO;
    return self.devModeEnabled && [bundleID isEqualToString:self.devModeBundleID];
}

@end
