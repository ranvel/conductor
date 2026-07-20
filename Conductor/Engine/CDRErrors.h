//
//  CDRErrors.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const CDRErrorDomain;

/// userInfo keys
extern NSString * const CDRErrorBundleIDKey;
extern NSString * const CDRErrorVendorURLKey;

typedef NS_ERROR_ENUM(CDRErrorDomain, CDRErrorCode) {
    // 1xx — discovery / configuration
    CDRErrorConductorJSONMalformed       = 100,
    CDRErrorUnsupportedFormatVersion     = 101,
    CDRErrorInsecureURLRefused           = 102,

    // 2xx — network / manifest
    CDRErrorManifestUnreachable          = 200,
    CDRErrorManifestMalformed            = 201,
    CDRErrorBundleIDManifestMismatch     = 202,
    CDRErrorDownloadFailed               = 203,
    CDRErrorChecksumMismatch             = 204,

    // 3xx — staging
    CDRErrorStagingCreateFailed          = 300,
    CDRErrorAttachFailed                 = 301,
    CDRErrorNoAppInArtifact              = 302,
    CDRErrorExtractFailed                = 303,

    // 4xx — verification
    CDRErrorInstalledUnsigned            = 400,
    CDRErrorInstalledAdHoc               = 401,
    CDRErrorBundleIDMismatch             = 402,
    CDRErrorDowngradeRefused             = 403,
    CDRErrorNotAnUpgrade                 = 404,
    CDRErrorSignatureInvalid             = 405,
    CDRErrorTeamIDMismatch               = 406,
    CDRErrorNotarizationRejected         = 407,

    // 5xx — install
    CDRErrorAppStillRunning              = 500,
    CDRErrorUserDeclinedQuit             = 501,
    CDRErrorSwapFailed                   = 502,
    CDRErrorPermissionDenied             = 503,
};

/// Builds a CDRErrorDomain error with localized description copy centralized here.
NSError *CDRError(CDRErrorCode code, NSString *_Nullable bundleID,
                  NSError *_Nullable underlying,
                  NSDictionary<NSString *, id> *_Nullable extraUserInfo);

NS_ASSUME_NONNULL_END
