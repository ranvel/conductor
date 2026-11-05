//
//  CDRInternetAccessPolicy.m
//  Conductor
//

#import "CDRInternetAccessPolicy.h"

const NSUInteger CDRInternetAccessPolicyMaxRows = 50;
static const NSUInteger kMaxTextLength = 300;

@interface CDRInternetAccessPolicyRow ()
@property (nonatomic, readwrite, copy) NSString *subject;
@property (nonatomic, readwrite, copy) NSString *purpose;
@property (nonatomic, readwrite) BOOL incoming;
@property (nonatomic, readwrite, copy, nullable) NSString *transport;
@end

@implementation CDRInternetAccessPolicyRow
@end

@interface CDRInternetAccessPolicy ()
@property (nonatomic, readwrite, copy) NSArray<CDRInternetAccessPolicyRow *> *rows;
@property (nonatomic, readwrite, copy, nullable) NSString *applicationDescription;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *warnings;
@end

@implementation CDRInternetAccessPolicy

/// A policy string as plain display text: the localization table is tried
/// first (developers often store a key and translate it), whitespace is
/// collapsed, and the length is capped. Nil for anything that isn't text.
static NSString *DisplayText(id raw, NSDictionary<NSString *, NSString *> *strings) {
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSString *text = raw;
    NSString *localized = strings[text];
    if ([localized isKindOfClass:[NSString class]] && localized.length > 0) text = localized;

    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableCharacterSet *separators = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
    [separators formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
    for (NSString *part in [text componentsSeparatedByCharactersInSet:separators]) {
        if (part.length > 0) [words addObject:part];
    }
    text = [words componentsJoinedByString:@" "];
    if (text.length == 0) return nil;
    if (text.length > kMaxTextLength) {
        NSRange keep = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kMaxTextLength - 1)];
        text = [[text substringToIndex:keep.length] stringByAppendingString:@"…"];
    }
    return text;
}

+ (nullable instancetype)policyWithPropertyList:(id)root strings:(NSDictionary<NSString *, NSString *> *)strings {
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = root;
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    NSMutableArray<CDRInternetAccessPolicyRow *> *rows = [NSMutableArray array];

    id connections = dict[@"Connections"];
    if (connections && ![connections isKindOfClass:[NSArray class]]) {
        [warnings addObject:@"`Connections` is not an array — ignored."];
        connections = nil;
    }
    NSUInteger skipped = 0;
    for (id entry in (NSArray *)connections) {
        if (rows.count >= CDRInternetAccessPolicyMaxRows) {
            [warnings addObject:[NSString stringWithFormat:@"%lu connections declared, showing the first %lu.",
                                 (unsigned long)[(NSArray *)connections count],
                                 (unsigned long)CDRInternetAccessPolicyMaxRows]];
            break;
        }
        NSString *host = [entry isKindOfClass:[NSDictionary class]] ? DisplayText(entry[@"Host"], nil) : nil;
        if (!host) {
            // A connection that names no remote end tells the user nothing.
            skipped++;
            continue;
        }
        CDRInternetAccessPolicyRow *row = [[CDRInternetAccessPolicyRow alloc] init];
        // A bare wildcard is the developer saying "wherever you point it".
        row.subject = [host isEqualToString:@"*"] ? @"Any server" : host;
        row.purpose = DisplayText(entry[@"Purpose"], strings) ?: @"No purpose given.";
        id incoming = entry[@"IsIncoming"];
        row.incoming = [incoming isKindOfClass:[NSNumber class]] && [incoming boolValue];

        NSMutableArray<NSString *> *transport = [NSMutableArray array];
        NSString *protocol = DisplayText(entry[@"NetworkProtocol"], nil);
        if (protocol) [transport addObject:protocol];
        id port = entry[@"Port"];
        if ([port isKindOfClass:[NSNumber class]]) port = [port stringValue];
        NSString *ports = DisplayText(port, nil);
        if (ports) [transport addObject:ports];
        row.transport = transport.count > 0 ? [transport componentsJoinedByString:@" "] : nil;
        [rows addObject:row];
    }
    if (skipped > 0) {
        [warnings addObject:[NSString stringWithFormat:@"%lu connection %@ no host — not shown.",
                             (unsigned long)skipped, skipped == 1 ? @"entry names" : @"entries name"]];
    }

    // Read, but not shown in this version.
    id services = dict[@"Services"];
    if ([services isKindOfClass:[NSArray class]] && [(NSArray *)services count] > 0) {
        [warnings addObject:[NSString stringWithFormat:@"%lu system service %@ declared — not shown.",
                             (unsigned long)[(NSArray *)services count],
                             [(NSArray *)services count] == 1 ? @"entry" : @"entries"]];
    }

    CDRInternetAccessPolicy *policy = [[CDRInternetAccessPolicy alloc] init];
    policy.rows = rows;
    policy.applicationDescription = DisplayText(dict[@"ApplicationDescription"], strings);
    policy.warnings = warnings;
    return policy;
}

/// The bundle's translation table for the policy, in the user's preferred
/// language among those it ships. Read as a file, never through NSBundle:
/// the staging path is reused across attempts and NSBundle caches per path.
+ (nullable NSDictionary<NSString *, NSString *> *)stringsInResources:(NSURL *)resources {
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:resources includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    NSMutableArray<NSString *> *languages = [NSMutableArray array];
    for (NSURL *url in contents) {
        if ([url.pathExtension isEqualToString:@"lproj"]) {
            NSURL *strings = [url URLByAppendingPathComponent:@"InternetAccessPolicy.strings"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:strings.path]) {
                [languages addObject:url.lastPathComponent.stringByDeletingPathExtension];
            }
        }
    }
    if (languages.count == 0) return nil;
    NSString *language = [NSBundle preferredLocalizationsFromArray:languages].firstObject
        ?: ([languages containsObject:@"en"] ? @"en" : languages.firstObject);
    NSURL *url = [[resources URLByAppendingPathComponent:[language stringByAppendingPathExtension:@"lproj"]]
        URLByAppendingPathComponent:@"InternetAccessPolicy.strings"];
    NSDictionary *table = [NSDictionary dictionaryWithContentsOfURL:url];
    return [table isKindOfClass:[NSDictionary class]] ? table : nil;
}

+ (nullable instancetype)policyForBundleAtURL:(NSURL *)bundleURL {
    NSURL *resources = [bundleURL URLByAppendingPathComponent:@"Contents/Resources" isDirectory:YES];
    id root = nil;
    for (NSString *relative in @[@"InternetAccessPolicy.plist", @"Base.lproj/InternetAccessPolicy.plist"]) {
        NSData *data = [NSData dataWithContentsOfURL:[resources URLByAppendingPathComponent:relative]];
        if (!data) continue;
        root = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                          format:NULL error:NULL];
        if (root) break;
    }
    if (!root) {
        NSData *json = [NSData dataWithContentsOfURL:
                        [resources URLByAppendingPathComponent:@"InternetAccessPolicy.json"]];
        if (json) root = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    }
    if (!root) return nil;
    return [self policyWithPropertyList:root strings:[self stringsInResources:resources]];
}

@end
