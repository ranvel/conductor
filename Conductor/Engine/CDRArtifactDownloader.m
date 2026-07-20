//
//  CDRArtifactDownloader.m
//  Conductor
//

#import "CDRArtifactDownloader.h"
#import "CDRDevModeSession.h"
#import "CDRErrors.h"
#import <CommonCrypto/CommonDigest.h>

@interface CDRArtifactDownloader ()
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic) NSURLSession *urlSession;
@end

@implementation CDRArtifactDownloader

- (instancetype)initWithSession:(CDRDevModeSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = session;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    config.URLCache = nil;
    _urlSession = [NSURLSession sessionWithConfiguration:config];
    return self;
}

static NSString *SHA256HexOfFile(NSURL *fileURL) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:fileURL.path];
    if (!fh) return nil;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    while (1) {
        @autoreleasepool {
            NSData *chunk = [fh readDataOfLength:1024 * 1024];
            if (chunk.length == 0) break;
            CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [fh closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

- (void)downloadArtifactAtURL:(NSURL *)url
                  forBundleID:(NSString *)bundleID
           toStagingDirectory:(NSURL *)stagingURL
               expectedSHA256:(NSString *)sha256
                     progress:(void (^)(double))progress
                   completion:(void (^)(NSURL *_Nullable, NSError *_Nullable))completion {
    if (![self.session allowsURL:url forBundleID:bundleID]) {
        completion(nil, CDRError(CDRErrorInsecureURLRefused, bundleID, nil, nil));
        return;
    }

    NSURLSessionDownloadTask *task = [self.urlSession downloadTaskWithURL:url
        completionHandler:^(NSURL *tempURL, NSURLResponse *response, NSError *transportError) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (transportError || !tempURL || (http && http.statusCode != 200)) {
            completion(nil, CDRError(CDRErrorDownloadFailed, bundleID, transportError, nil));
            return;
        }

        // Move into staging immediately — NSURLSession deletes tempURL when
        // this handler returns, and staging is where cleanup is unified.
        NSString *name = url.lastPathComponent.length > 0 ? url.lastPathComponent : @"artifact";
        NSURL *destination = [stagingURL URLByAppendingPathComponent:name];
        NSError *moveError = nil;
        [[NSFileManager defaultManager] removeItemAtURL:destination error:NULL];
        if (![[NSFileManager defaultManager] moveItemAtURL:tempURL toURL:destination error:&moveError]) {
            completion(nil, CDRError(CDRErrorDownloadFailed, bundleID, moveError, nil));
            return;
        }

        if (sha256.length > 0) {
            NSString *actual = SHA256HexOfFile(destination);
            if (![actual isEqualToString:sha256.lowercaseString]) {
                completion(nil, CDRError(CDRErrorChecksumMismatch, bundleID, nil, nil));
                return;
            }
        }
        completion(destination, nil);
    }];

    if (progress) {
        // Coarse polling is enough for the milestone log view.
        NSProgress *taskProgress = task.progress;
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            if (taskProgress.isFinished || taskProgress.isCancelled) {
                [t invalidate];
                return;
            }
            progress(taskProgress.fractionCompleted);
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    }
    [task resume];
}

@end
