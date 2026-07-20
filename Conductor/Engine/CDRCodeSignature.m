//
//  CDRCodeSignature.m
//  Conductor
//

#import "CDRCodeSignature.h"
#import "CDRErrors.h"
#import <Security/Security.h>

/// One constant so enabling kSecCSCheckNestedCode later is a one-line change.
static const SecCSFlags kCDRValidationFlags = kSecCSCheckAllArchitectures | kSecCSStrictValidate;

@implementation CDRCodeSignature

static NSError *OSStatusError(OSStatus status, CFErrorRef _Nullable cfError) {
    if (cfError) return CFBridgingRelease(cfError);
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
}

+ (nullable NSString *)teamIdentifierForBundleAtURL:(NSURL *)url error:(NSError **)error {
    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &staticCode);
    if (status != errSecSuccess || !staticCode) {
        if (error) *error = CDRError(CDRErrorInstalledUnsigned, nil, OSStatusError(status, NULL), nil);
        return nil;
    }

    CFDictionaryRef infoRef = NULL;
    status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &infoRef);
    CFRelease(staticCode);
    if (status != errSecSuccess || !infoRef) {
        if (error) *error = CDRError(CDRErrorInstalledUnsigned, nil, OSStatusError(status, NULL), nil);
        return nil;
    }

    NSDictionary *info = CFBridgingRelease(infoRef);
    // An unsigned bundle yields signing info with no identifier at all;
    // an ad-hoc or non-Developer-ID signature has an identifier but no team.
    if (info[(__bridge NSString *)kSecCodeInfoIdentifier] == nil) {
        if (error) *error = CDRError(CDRErrorInstalledUnsigned, nil, nil, nil);
        return nil;
    }
    NSString *team = info[(__bridge NSString *)kSecCodeInfoTeamIdentifier];
    if (![team isKindOfClass:[NSString class]] || team.length == 0) {
        if (error) *error = CDRError(CDRErrorInstalledAdHoc, nil, nil, nil);
        return nil;
    }
    return team;
}

+ (BOOL)validateBundleAtURL:(NSURL *)url
               pinnedTeamID:(NSString *)teamID
                      error:(NSError **)error {
    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &staticCode);
    if (status != errSecSuccess || !staticCode) {
        if (error) *error = CDRError(CDRErrorSignatureInvalid, nil, OSStatusError(status, NULL), nil);
        return NO;
    }

    NSString *requirementString = [NSString stringWithFormat:
        @"anchor apple generic and certificate leaf[subject.OU] = \"%@\"", teamID];
    SecRequirementRef requirement = NULL;
    status = SecRequirementCreateWithString((__bridge CFStringRef)requirementString,
                                            kSecCSDefaultFlags, &requirement);
    if (status != errSecSuccess || !requirement) {
        CFRelease(staticCode);
        if (error) *error = CDRError(CDRErrorSignatureInvalid, nil, OSStatusError(status, NULL), nil);
        return NO;
    }

    CFErrorRef validityError = NULL;
    status = SecStaticCodeCheckValidityWithErrors(staticCode, kCDRValidationFlags,
                                                  requirement, &validityError);
    CFRelease(requirement);
    CFRelease(staticCode);

    if (status == errSecSuccess) {
        if (validityError) CFRelease(validityError);
        return YES;
    }

    // errSecCSReqFailed with an otherwise-valid signature means the pinned
    // requirement (the team) failed — a different developer's valid signature.
    CDRErrorCode code = (status == errSecCSReqFailed) ? CDRErrorTeamIDMismatch
                                                      : CDRErrorSignatureInvalid;
    if (error) *error = CDRError(code, nil, OSStatusError(status, validityError), nil);
    else if (validityError) CFRelease(validityError);
    return NO;
}

@end
