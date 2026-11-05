//
//  CDRManifest.m
//  Conductor
//

#import "CDRManifest.h"
#import "CDRErrors.h"
#import "CDRVersion.h"

static const NSInteger kCDRSupportedManifestVersion = 1;

const NSUInteger CDRManifestMaxHistoryEntries = 10;
const NSUInteger CDRManifestMaxNotesPerRelease = 100;

/// "YYYY-MM-DD" → local noon of that calendar day, so the date a vendor wrote
/// is the date every user sees regardless of time zone. Nil for anything that
/// is not a real calendar day in that exact form.
static NSDate *CDRDateFromCalendarDayString(id raw) {
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSString *string = raw;
    if (string.length != 10) return nil;
    NSCharacterSet *nonDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@"-"];
    if (parts.count != 3 || parts[0].length != 4 || parts[1].length != 2 || parts[2].length != 2) return nil;
    for (NSString *part in parts) {
        if ([part rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return nil;
    }

    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = parts[0].integerValue;
    components.month = parts[1].integerValue;
    components.day = parts[2].integerValue;
    components.hour = 12;
    NSDate *date = [calendar dateFromComponents:components];
    if (!date) return nil;
    // dateFromComponents: rolls "02-31" over into March; refuse instead.
    NSDateComponents *back = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                         fromDate:date];
    if (back.year != components.year || back.month != components.month || back.day != components.day) return nil;
    return date;
}

/// Parses one `notes` array. Every problem degrades to a warning: release
/// notes are display data and must never fail a manifest.
static NSArray<CDRReleaseNote *> *CDRParseNotes(id raw, NSString *label,
                                                 NSUInteger *outUndisplayable,
                                                 NSMutableArray<NSString *> *warnings) {
    *outUndisplayable = 0;
    if (!raw) return @[];
    if (![raw isKindOfClass:[NSArray class]]) {
        [warnings addObject:[NSString stringWithFormat:@"%@: `notes` is not an array — ignored.", label]];
        return @[];
    }
    NSArray *items = raw;
    if (items.count > CDRManifestMaxNotesPerRelease) {
        [warnings addObject:[NSString stringWithFormat:@"%@: %lu notes, reading the first %lu.", label,
                             (unsigned long)items.count, (unsigned long)CDRManifestMaxNotesPerRelease]];
        items = [items subarrayWithRange:NSMakeRange(0, CDRManifestMaxNotesPerRelease)];
    }

    NSMutableArray<CDRReleaseNote *> *notes = [NSMutableArray array];
    NSUInteger index = 0;
    for (id item in items) {
        index++;
        if (![item isKindOfClass:[NSDictionary class]]) {
            [warnings addObject:[NSString stringWithFormat:@"%@: note %lu is not an object — dropped.",
                                 label, (unsigned long)index]];
            continue;
        }
        NSString *key = item[@"type"];
        if (![key isKindOfClass:[NSString class]] || key.length == 0) {
            [warnings addObject:[NSString stringWithFormat:@"%@: note %lu has no `type` — dropped.",
                                 label, (unsigned long)index]];
            continue;
        }
        CDRReleaseNoteType type;
        if (!CDRReleaseNoteTypeFromKey(key, &type)) {
            // Rejected, never guessed at — but counted, so the UI can say
            // that something was said which this Conductor can't display.
            (*outUndisplayable)++;
            [warnings addObject:[NSString stringWithFormat:@"%@: note %lu has unknown type \"%@\" — dropped.",
                                 label, (unsigned long)index, key]];
            continue;
        }
        if (!CDRReleaseNoteTypeIsDeveloperAuthored(type)) {
            // "retracted" is Conductor's to say, never the manifest's.
            (*outUndisplayable)++;
            [warnings addObject:[NSString stringWithFormat:
                                 @"%@: note %lu claims type \"%@\", which a manifest may not carry — dropped.",
                                 label, (unsigned long)index, key]];
            continue;
        }
        BOOL truncated = NO;
        NSString *text = CDRSanitizedReleaseNoteText(item[@"text"], &truncated);
        if (!text) {
            [warnings addObject:[NSString stringWithFormat:@"%@: note %lu has no text — dropped.",
                                 label, (unsigned long)index]];
            continue;
        }
        if (truncated) {
            [warnings addObject:[NSString stringWithFormat:@"%@: note %lu is longer than %lu characters — truncated.",
                                 label, (unsigned long)index, (unsigned long)CDRReleaseNoteMaxTextLength]];
        }
        [notes addObject:[CDRReleaseNote noteWithType:type text:text]];
    }
    return notes;
}

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

    [m parseDisplayFieldsFromDictionary:dict];
    return m;
}

/// spec.md §3.5 — `notes`, `released`, `size`, `history`. All optional, all
/// display data: nothing here can fail the manifest or reach verification.
- (void)parseDisplayFieldsFromDictionary:(NSDictionary *)dict {
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];

    NSDate *released = nil;
    if (dict[@"released"]) {
        released = CDRDateFromCalendarDayString(dict[@"released"]);
        if (!released) [warnings addObject:@"`released` is not a YYYY-MM-DD date — ignored."];
    }
    NSUInteger undisplayable = 0;
    NSArray<CDRReleaseNote *> *notes = CDRParseNotes(dict[@"notes"],
        [NSString stringWithFormat:@"version %@", _version], &undisplayable, warnings);
    _advertisedRelease = [[CDRRelease alloc] initWithVersion:_version date:released notes:notes
                            undisplayableNoteCount:undisplayable];

    id size = dict[@"size"];
    if (size) {
        // A JSON boolean is an NSNumber too; it is not a byte count.
        BOOL isNumber = [size isKindOfClass:[NSNumber class]]
            && CFGetTypeID((__bridge CFTypeRef)size) != CFBooleanGetTypeID();
        if (isNumber && [size longLongValue] > 0) {
            _artifactSize = @([size longLongValue]);
        } else {
            [warnings addObject:@"`size` is not a positive number of bytes — ignored."];
        }
    }

    NSMutableArray<CDRRelease *> *history = [NSMutableArray array];
    id rawHistory = dict[@"history"];
    if (rawHistory && ![rawHistory isKindOfClass:[NSArray class]]) {
        [warnings addObject:@"`history` is not an array — ignored."];
    } else if (rawHistory) {
        NSArray *entries = rawHistory;
        if (entries.count > CDRManifestMaxHistoryEntries) {
            [warnings addObject:[NSString stringWithFormat:@"`history` has %lu entries, reading the first %lu.",
                                 (unsigned long)entries.count, (unsigned long)CDRManifestMaxHistoryEntries]];
            entries = [entries subarrayWithRange:NSMakeRange(0, CDRManifestMaxHistoryEntries)];
        }
        NSUInteger index = 0;
        for (id entry in entries) {
            index++;
            NSString *entryVersion = [entry isKindOfClass:[NSDictionary class]] ? entry[@"version"] : nil;
            if (![entryVersion isKindOfClass:[NSString class]] || entryVersion.length == 0) {
                [warnings addObject:[NSString stringWithFormat:@"`history` entry %lu has no version — dropped.",
                                     (unsigned long)index]];
                continue;
            }
            NSDate *date = nil;
            if (entry[@"date"]) {
                date = CDRDateFromCalendarDayString(entry[@"date"]);
                if (!date) {
                    [warnings addObject:[NSString stringWithFormat:
                                         @"`history` %@: `date` is not a YYYY-MM-DD date — ignored.", entryVersion]];
                }
            }
            NSUInteger entryUndisplayable = 0;
            NSArray<CDRReleaseNote *> *entryNotes = CDRParseNotes(entry[@"notes"],
                [NSString stringWithFormat:@"history %@", entryVersion], &entryUndisplayable, warnings);
            [history addObject:[[CDRRelease alloc] initWithVersion:entryVersion date:date notes:entryNotes
                                            undisplayableNoteCount:entryUndisplayable]];
        }
    }
    _history = [history copy];
    _parseWarnings = [warnings copy];
}

- (NSArray<CDRRelease *> *)releasesNewerThanVersion:(NSString *)installedVersion {
    if ([CDRVersion compare:self.version to:installedVersion] != NSOrderedDescending) return @[];

    NSMutableArray<CDRRelease *> *skipped = [NSMutableArray array];
    for (CDRRelease *entry in self.history) {
        // Strictly between installed and advertised. An entry for the
        // advertised version itself is ignored: top-level `notes` is the one
        // place those live, so there is nothing to keep in sync.
        if ([CDRVersion compare:entry.version to:installedVersion] != NSOrderedDescending) continue;
        if ([CDRVersion compare:entry.version to:self.version] != NSOrderedAscending) continue;
        BOOL duplicate = NO;
        for (CDRRelease *kept in skipped) {
            if ([CDRVersion compare:kept.version to:entry.version] == NSOrderedSame) { duplicate = YES; break; }
        }
        if (!duplicate) [skipped addObject:entry];
    }
    // Newest first, whatever order the manifest used.
    [skipped sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(CDRRelease *a, CDRRelease *b) {
        return [CDRVersion compare:b.version to:a.version];
    }];

    NSMutableArray<CDRRelease *> *result = [NSMutableArray arrayWithObject:self.advertisedRelease];
    [result addObjectsFromArray:skipped];
    return result;
}

@end
