//
//  CDRBundleInspector.m
//  Conductor
//

#import "CDRBundleInspector.h"
#import <Security/Security.h>

@implementation CDRBundleInspector

+ (nullable NSString *)developerNameForBundleAtURL:(NSURL *)url {
    SecStaticCodeRef staticCode = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &staticCode) != errSecSuccess
        || !staticCode) {
        return nil;
    }
    CFDictionaryRef infoRef = NULL;
    OSStatus status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &infoRef);
    CFRelease(staticCode);
    if (status != errSecSuccess || !infoRef) return nil;
    NSDictionary *info = CFBridgingRelease(infoRef);

    NSArray *certificates = info[(__bridge NSString *)kSecCodeInfoCertificates];
    if (![certificates isKindOfClass:[NSArray class]] || certificates.count == 0) return nil;
    SecCertificateRef leaf = (__bridge SecCertificateRef)certificates.firstObject;

    // Preferred: the subject's Organization attribute.
    NSArray *keys = @[(__bridge NSString *)kSecOIDX509V1SubjectName];
    NSDictionary *values = CFBridgingRelease(
        SecCertificateCopyValues(leaf, (__bridge CFArrayRef)keys, NULL));
    NSArray *subject = values[(__bridge NSString *)kSecOIDX509V1SubjectName][(__bridge NSString *)kSecPropertyKeyValue];
    if ([subject isKindOfClass:[NSArray class]]) {
        for (NSDictionary *attribute in subject) {
            if (![attribute isKindOfClass:[NSDictionary class]]) continue;
            NSString *label = attribute[(__bridge NSString *)kSecPropertyKeyLabel];
            NSString *value = attribute[(__bridge NSString *)kSecPropertyKeyValue];
            if ([label isEqual:(__bridge NSString *)kSecOIDOrganizationName]
                && [value isKindOfClass:[NSString class]] && value.length > 0) {
                return value;
            }
        }
    }

    // Fallback: "Developer ID Application: Cedar Syntax LLC (F252L9GUBW)".
    NSString *summary = CFBridgingRelease(SecCertificateCopySubjectSummary(leaf));
    if (summary.length == 0) return nil;
    NSRange colon = [summary rangeOfString:@": "];
    if (colon.location != NSNotFound) summary = [summary substringFromIndex:NSMaxRange(colon)];
    NSRange paren = [summary rangeOfString:@" (" options:NSBackwardsSearch];
    if (paren.location != NSNotFound && [summary hasSuffix:@")"]) {
        summary = [summary substringToIndex:paren.location];
    }
    return summary.length > 0 ? summary : nil;
}

@end
