//
//  CDRErrors.m
//  Conductor
//

#import "CDRErrors.h"

NSErrorDomain const CDRErrorDomain = @"com.ranvel.Conductor.ErrorDomain";

NSString * const CDRErrorBundleIDKey  = @"CDRErrorBundleID";
NSString * const CDRErrorVendorURLKey = @"CDRErrorVendorURL";
NSString * const CDRErrorIsRetractionKey = @"CDRErrorIsRetraction";

static NSString *CDRLocalizedDescriptionForCode(CDRErrorCode code, NSString *_Nullable bundleID) {
    NSString *app = bundleID ?: @"the app";
    switch (code) {
        case CDRErrorConductorJSONMalformed:
            return [NSString stringWithFormat:@"%@ has a malformed conductor.json.", app];
        case CDRErrorUnsupportedFormatVersion:
            return [NSString stringWithFormat:@"%@ uses a conductor.json format version this Conductor does not understand.", app];
        case CDRErrorInsecureURLRefused:
            return [NSString stringWithFormat:@"%@ declares a non-HTTPS URL. Insecure connections are only permitted in dev mode.", app];
        case CDRErrorManifestUnreachable:
            return [NSString stringWithFormat:@"The update server for %@ could not be reached.", app];
        case CDRErrorManifestMalformed:
            return [NSString stringWithFormat:@"The update manifest for %@ is malformed.", app];
        case CDRErrorBundleIDManifestMismatch:
            return [NSString stringWithFormat:@"The update manifest for %@ describes a different app. Refusing to continue.", app];
        case CDRErrorDownloadFailed:
            return [NSString stringWithFormat:@"Downloading the update for %@ failed.", app];
        case CDRErrorChecksumMismatch:
            return [NSString stringWithFormat:@"The downloaded update for %@ is corrupt (checksum mismatch).", app];
        case CDRErrorStagingCreateFailed:
            return @"Could not create the staging directory.";
        case CDRErrorAttachFailed:
            return [NSString stringWithFormat:@"The downloaded disk image for %@ could not be opened.", app];
        case CDRErrorNoAppInArtifact:
            return [NSString stringWithFormat:@"The downloaded update for %@ does not contain an application.", app];
        case CDRErrorExtractFailed:
            return [NSString stringWithFormat:@"Extracting the update for %@ failed.", app];
        case CDRErrorInstalledUnsigned:
            return [NSString stringWithFormat:@"%@ is not code-signed. Conductor only manages signed and notarized apps.", app];
        case CDRErrorInstalledAdHoc:
            return [NSString stringWithFormat:@"%@ is ad-hoc signed (no Developer ID). Conductor only manages signed and notarized apps.", app];
        case CDRErrorBundleIDMismatch:
            return [NSString stringWithFormat:@"The downloaded update is not %@ (bundle identifier mismatch).", app];
        case CDRErrorDowngradeRefused:
            return [NSString stringWithFormat:@"The advertised update for %@ is older than the installed version. Downgrades are refused.", app];
        case CDRErrorNotAnUpgrade:
            return [NSString stringWithFormat:@"The downloaded update for %@ is not newer than the installed version.", app];
        case CDRErrorSignatureInvalid:
            return [NSString stringWithFormat:@"The downloaded update for %@ has an invalid code signature.", app];
        case CDRErrorTeamIDMismatch:
            return [NSString stringWithFormat:@"The downloaded update for %@ is signed by a different developer than the installed copy. Refusing to install.", app];
        case CDRErrorNotarizationRejected:
            return [NSString stringWithFormat:@"The downloaded update for %@ is not notarized by Apple.", app];
        case CDRErrorAppStillRunning:
            return [NSString stringWithFormat:@"%@ is still running.", app];
        case CDRErrorUserDeclinedQuit:
            return @"Update cancelled.";
        case CDRErrorSwapFailed:
            return [NSString stringWithFormat:@"Replacing %@ failed. The installed copy was not modified.", app];
        case CDRErrorPermissionDenied:
            return [NSString stringWithFormat:@"Conductor does not have permission to replace %@ (it may be owned by another user). Update it manually, or adjust its ownership.", app];
        case CDRErrorUpdateCancelled:
            return [NSString stringWithFormat:@"The pending update for %@ was canceled. Nothing was changed.", app];
        case CDRErrorApprovalDeclined:
            return [NSString stringWithFormat:@"The update for %@ was not approved. Nothing was changed.", app];
    }
    return @"An unknown error occurred.";
}

NSError *CDRError(CDRErrorCode code, NSString *_Nullable bundleID,
                  NSError *_Nullable underlying,
                  NSDictionary<NSString *, id> *_Nullable extraUserInfo) {
    NSMutableDictionary<NSString *, id> *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = CDRLocalizedDescriptionForCode(code, bundleID);
    userInfo[CDRErrorBundleIDKey] = bundleID;
    userInfo[NSUnderlyingErrorKey] = underlying;
    if (extraUserInfo) {
        [userInfo addEntriesFromDictionary:extraUserInfo];
    }
    return [NSError errorWithDomain:CDRErrorDomain code:code userInfo:userInfo];
}
