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

+ (NSString *)infoPlistRelativePath {
    return @"Contents/Info.plist";
}

/// NSBundle caches the info dictionary per path for the process lifetime, so a
/// bundle swapped in place would read back its pre-swap identity forever.
/// Always read the plist directly.
+ (nullable NSDictionary *)infoPlistForAppAtURL:(NSURL *)appURL {
    return [NSDictionary dictionaryWithContentsOfURL:
        [appURL URLByAppendingPathComponent:[self infoPlistRelativePath]]];
}

static NSString *_Nullable CDRStringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

+ (nullable instancetype)registrationForAppAtURL:(NSURL *)appURL error:(NSError **)error {
    NSDictionary *info = [self infoPlistForAppAtURL:appURL];
    NSString *bundleID = CDRStringOrNil(info[@"CFBundleIdentifier"]);

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

    NSString *shortVersion = CDRStringOrNil(info[@"CFBundleShortVersionString"]);
    NSString *buildVersion = CDRStringOrNil(info[@"CFBundleVersion"]);
    if (bundleID.length == 0 || shortVersion.length == 0) {
        if (error) *error = CDRError(CDRErrorConductorJSONMalformed, bundleID, nil, nil);
        return nil;
    }

    CDRAppRegistration *reg = [[CDRAppRegistration alloc] init];
    reg->_appURL = appURL;
    reg->_bundleID = [bundleID copy];
    reg->_installedShortVersion = [shortVersion copy];
    reg->_installedBuildVersion = [buildVersion copy];
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

- (instancetype)registrationWithInstalledShortVersion:(NSString *)shortVersion
                                         buildVersion:(nullable NSString *)buildVersion {
    CDRAppRegistration *reg = [[CDRAppRegistration alloc] init];
    reg->_appURL = _appURL;
    reg->_bundleID = _bundleID;
    reg->_installedShortVersion = [shortVersion copy];
    reg->_installedBuildVersion = [buildVersion copy];
    reg->_updateURL = _updateURL;
    reg->_fallbackURL = _fallbackURL;
    reg->_vendorURL = _vendorURL;
    return reg;
}

- (instancetype)registrationByRefreshingInstalledVersion {
    NSDictionary *info = [[self class] infoPlistForAppAtURL:self.appURL];
    NSString *bundleID = CDRStringOrNil(info[@"CFBundleIdentifier"]);
    NSString *shortVersion = CDRStringOrNil(info[@"CFBundleShortVersionString"]);
    NSString *buildVersion = CDRStringOrNil(info[@"CFBundleVersion"]);
    // Unreadable plist or a different bundle at this path (removed/replaced
    // out-of-band): not a version change — leave it to the next full rescan.
    if (![bundleID isEqualToString:self.bundleID] || shortVersion.length == 0) return self;
    BOOL sameShort = [shortVersion isEqualToString:self.installedShortVersion];
    BOOL sameBuild = (buildVersion == self.installedBuildVersion)
        || [buildVersion isEqualToString:self.installedBuildVersion];
    if (sameShort && sameBuild) return self;
    return [self registrationWithInstalledShortVersion:shortVersion buildVersion:buildVersion];
}

@end
