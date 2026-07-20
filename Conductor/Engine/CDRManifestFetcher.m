//
//  CDRManifestFetcher.m
//  Conductor
//

#import "CDRManifestFetcher.h"
#import "CDRAppRegistration.h"
#import "CDRDevModeSession.h"
#import "CDRManifest.h"
#import "CDRErrors.h"

@interface CDRManifestFetcher ()
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) NSURLSession *urlSession;
@end

@implementation CDRManifestFetcher

- (instancetype)initWithSession:(CDRDevModeSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = session;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    config.URLCache = nil;
    config.timeoutIntervalForRequest = 30;
    _urlSession = [NSURLSession sessionWithConfiguration:config];
    return self;
}

static NSDictionary *ExtraInfo(CDRAppRegistration *reg) {
    return reg.vendorURL ? @{CDRErrorVendorURLKey: reg.vendorURL} : nil;
}

- (void)fetchManifestForRegistration:(CDRAppRegistration *)registration
                          completion:(void (^)(CDRManifest *_Nullable, NSError *_Nullable))completion {
    [self fetchFromURL:registration.updateURL
          registration:registration
            completion:^(CDRManifest *manifest, NSError *error, BOOL unreachable) {
        if (manifest || !unreachable || !registration.fallbackURL) {
            completion(manifest, error);
            return;
        }
        // Primary unreachable → try the fallback. It exists for
        // unresponsiveness only, never as a second opinion.
        [self fetchFromURL:registration.fallbackURL
              registration:registration
                completion:^(CDRManifest *fbManifest, NSError *fbError, BOOL fbUnreachable) {
            completion(fbManifest, fbError);
        }];
    }];
}

/// unreachable=YES means a transport-level failure (worth trying the fallback),
/// as opposed to a policy refusal or a malformed/mismatched manifest (not).
- (void)fetchFromURL:(NSURL *)url
        registration:(CDRAppRegistration *)registration
          completion:(void (^)(CDRManifest *_Nullable, NSError *_Nullable, BOOL unreachable))completion {
    if (![self.session allowsURL:url forBundleID:registration.bundleID]) {
        completion(nil, CDRError(CDRErrorInsecureURLRefused, registration.bundleID, nil, ExtraInfo(registration)), NO);
        return;
    }

    NSURLSessionDataTask *task = [self.urlSession dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *transportError) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (transportError || !data || (http && http.statusCode != 200)) {
            completion(nil, CDRError(CDRErrorManifestUnreachable, registration.bundleID,
                                     transportError, ExtraInfo(registration)), YES);
            return;
        }

        NSError *parseError = nil;
        CDRManifest *manifest = [CDRManifest manifestWithData:data error:&parseError];
        if (!manifest) {
            completion(nil, parseError, NO);
            return;
        }
        if (![manifest.bundleID isEqualToString:registration.bundleID]) {
            completion(nil, CDRError(CDRErrorBundleIDManifestMismatch, registration.bundleID,
                                     nil, ExtraInfo(registration)), NO);
            return;
        }
        completion(manifest, nil, NO);
    }];
    [task resume];
}

@end
