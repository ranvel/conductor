//
//  CDRAppRegistration.m
//  Conductor
//

#import "CDRAppRegistration.h"
#import "CDRErrors.h"

static const NSInteger kCDRSupportedConductorJSONVersion = 1;

@implementation CDRAppRegistration

+ (NSString *)conductorJSONRelativePath {
    return @"Contents/Resources/conductor.json";
}

+ (nullable instancetype)registrationForAppAtURL:(NSURL *)appURL error:(NSError **)error {
    NSBundle *bundle = [NSBundle bundleWithURL:appURL];
    NSString *bundleID = bundle.bundleIdentifier;

    NSURL *jsonURL = [appURL URLByAppendingPathComponent:[self conductorJSONRelativePath]];
    NSData *data = [NSData dataWithContentsOfURL:jsonURL];
    if (!data) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, nil, nil);
        return nil;
    }

    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![root isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, jsonError, nil);
        return nil;
    }
    NSDictionary *dict = root;

    NSNumber *format = dict[@"conductor"];
    if (![format isKindOfClass:[NSNumber class]]) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, nil, nil);
        return nil;
    }
    if (format.integerValue != kCDRSupportedConductorJSONVersion) {
        if (error) *error = CDRError(CDRErrorUnsupportedFormatVersion, bundleID, nil, nil);
        return nil;
    }

    NSString *updateString = dict[@"update_url"];
    if (![updateString isKindOfClass:[NSString class]] || updateString.length == 0) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, nil, nil);
        return nil;
    }
    NSURL *updateURL = [NSURL URLWithString:updateString];
    if (!updateURL || !updateURL.scheme || !updateURL.host) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, nil, nil);
        return nil;
    }

    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (bundleID.length == 0 || ![shortVersion isKindOfClass:[NSString class]] || shortVersion.length == 0) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, nil, nil);
        return nil;
    }

    CDRAppRegistration *reg = [[CDRAppRegistration alloc] init];
    reg->_appURL = appURL;
    reg->_bundleID = [bundleID copy];
    reg->_installedShortVersion = [shortVersion copy];
    reg->_installedBuildVersion = [buildVersion isKindOfClass:[NSString class]] && buildVersion.length > 0 ? [buildVersion copy] : nil;
    reg->_updateURL = updateURL;

    NSString *fallbackString = dict[@"fallback_url"];
    if ([fallbackString isKindOfClass:[NSString class]] && fallbackString.length > 0) {
        reg->_fallbackURL = [NSURL URLWithString:fallbackString];
    }
    NSString *vendorString = dict[@"vendor_url"];
    if ([vendorString isKindOfClass:[NSString class]] && vendorString.length > 0) {
        reg->_vendorURL = [NSURL URLWithString:vendorString];
    }

    return reg;
}

@end
