//
//  CDRManifest.m
//  Conductor
//

#import "CDRManifest.h"
#import "CDRErrors.h"

static const NSInteger kCDRSupportedManifestVersion = 1;

@implementation CDRManifest

+ (nullable instancetype)manifestWithData:(NSData *)data error:(NSError **)error {
    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![root isKindOfClass:[NSDictionary class]]) {
        if (error) *error = CDRError(CDRErrorManifestMalformed, nil, jsonError, nil);
        return nil;
    }
    NSDictionary *dict = root;

    NSNumber *format = dict[@"conductor_manifest"];
    if (![format isKindOfClass:[NSNumber class]]) {
        if (error) *error = CDRError(CDRErrorManifestMalformed, nil, nil, nil);
        return nil;
    }
    if (format.integerValue != kCDRSupportedManifestVersion) {
        if (error) *error = CDRError(CDRErrorUnsupportedFormatVersion, nil, nil, nil);
        return nil;
    }

    NSString *bundleID = dict[@"bundle_id"];
    NSString *version = dict[@"version"];
    NSString *urlString = dict[@"url"];
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0 ||
        ![version isKindOfClass:[NSString class]] || version.length == 0 ||
        ![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
        if (error) *error = CDRError(CDRErrorManifestMalformed, bundleID, nil, nil);
        return nil;
    }
    NSURL *artifactURL = [NSURL URLWithString:urlString];
    if (!artifactURL || !artifactURL.scheme || !artifactURL.host) {
        if (error) *error = CDRError(CDRErrorManifestMalformed, bundleID, nil, nil);
        return nil;
    }

    CDRManifest *m = [[CDRManifest alloc] init];
    m->_formatVersion = format.integerValue;
    m->_bundleID = [bundleID copy];
    m->_version = [version copy];
    m->_artifactURL = artifactURL;

    NSString *build = dict[@"build"];
    m->_build = [build isKindOfClass:[NSString class]] && build.length > 0 ? [build copy] : nil;

    NSString *sha = dict[@"sha256"];
    m->_sha256 = [sha isKindOfClass:[NSString class]] && sha.length > 0 ? [sha.lowercaseString copy] : nil;

    NSString *urgency = dict[@"urgency"];
    m->_urgency = CDRUrgencyNone;
    if ([urgency isKindOfClass:[NSString class]]) {
        // Unknown tokens are ignored (forward compatibility, deferral.md).
        if ([urgency isEqualToString:@"system_risk"]) m->_urgency = CDRUrgencySystemRisk;
        else if ([urgency isEqualToString:@"data_loss"]) m->_urgency = CDRUrgencyDataLoss;
        else if ([urgency isEqualToString:@"data_exfiltration"]) m->_urgency = CDRUrgencyDataExfiltration;
    }

    NSString *changelog = dict[@"changelog_url"];
    if ([changelog isKindOfClass:[NSString class]] && changelog.length > 0) {
        m->_changelogURL = [NSURL URLWithString:changelog];
    }

    NSString *minSystem = dict[@"min_system_version"];
    m->_minSystemVersion = [minSystem isKindOfClass:[NSString class]] && minSystem.length > 0 ? [minSystem copy] : nil;

    return m;
}

@end
