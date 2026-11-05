//
//  CDRManifestTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRManifest.h"
#import "CDRErrors.h"

@interface CDRManifestTests : XCTestCase
@end

@implementation CDRManifestTests

static NSData *JSONData(NSDictionary *dict) {
    return [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
}

static NSDictionary *ValidManifestDict(void) {
    return @{
        @"conductor_manifest": @1,
        @"bundle_id": @"com.example.app",
        @"version": @"1.1",
        @"url": @"https://example.com/app-1.1.dmg",
    };
}

- (void)testValidMinimalManifest {
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(ValidManifestDict()) error:&error];
    XCTAssertNotNil(m);
    XCTAssertNil(error);
    XCTAssertEqualObjects(m.bundleID, @"com.example.app");
    XCTAssertEqualObjects(m.version, @"1.1");
    XCTAssertEqualObjects(m.artifactURL.absoluteString, @"https://example.com/app-1.1.dmg");
    XCTAssertNil(m.build);
    XCTAssertNil(m.sha256);
    XCTAssertEqual(m.urgency, CDRUrgencyNone);
}

- (void)testOptionalFields {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"build"] = @"110";
    dict[@"sha256"] = @"ABCDEF";
    dict[@"changelog_url"] = @"https://example.com/changelog";
    dict[@"min_system_version"] = @"13.0";
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
    XCTAssertNotNil(m);
    XCTAssertEqualObjects(m.build, @"110");
    XCTAssertEqualObjects(m.sha256, @"abcdef"); // normalized to lowercase
    XCTAssertEqualObjects(m.changelogURL.host, @"example.com");
    XCTAssertEqualObjects(m.minSystemVersion, @"13.0");
}

- (void)testMissingRequiredFieldFails {
    for (NSString *key in @[@"conductor_manifest", @"bundle_id", @"version", @"url"]) {
        NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
        [dict removeObjectForKey:key];
        NSError *error = nil;
        CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
        XCTAssertNil(m, @"expected failure with %@ missing", key);
        XCTAssertEqualObjects(error.domain, CDRErrorDomain);
    }
}

- (void)testUnsupportedFormatVersionFails {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"conductor_manifest"] = @2;
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
    XCTAssertNil(m);
    XCTAssertEqual(error.code, CDRErrorUnsupportedFormatVersion);
}

- (void)testUrgencyTokens {
    NSDictionary<NSString *, NSNumber *> *cases = @{
        @"system_risk": @(CDRUrgencySystemRisk),
        @"data_loss": @(CDRUrgencyDataLoss),
        @"data_exfiltration": @(CDRUrgencyDataExfiltration),
    };
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *token, NSNumber *expected, BOOL *stop) {
        NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
        dict[@"urgency"] = token;
        CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:NULL];
        XCTAssertEqual(m.urgency, (CDRUrgency)expected.integerValue);
    }];
}

- (void)testUnknownUrgencyTokenIsIgnored {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"urgency"] = @"mildly_exciting_new_features";
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:NULL];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.urgency, CDRUrgencyNone);
}

- (void)testGarbageDataFails {
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    XCTAssertNil(m);
    XCTAssertEqual(error.code, CDRErrorManifestMalformed);
}

- (void)testRelativeArtifactURLFails {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    dict[@"url"] = @"downloads/app.dmg";
    NSError *error = nil;
    CDRManifest *m = [CDRManifest manifestWithData:JSONData(dict) error:&error];
    XCTAssertNil(m);
    XCTAssertEqual(error.code, CDRErrorManifestMalformed);
}

#pragma mark - Release notes (spec.md §3.5)

static NSDictionary *Note(NSString *type, NSString *text) {
    return @{@"type": type, @"text": text};
}

static CDRManifest *ManifestWith(NSDictionary *extra) {
    NSMutableDictionary *dict = [ValidManifestDict() mutableCopy];
    [dict addEntriesFromDictionary:extra];
    return [CDRManifest manifestWithData:JSONData(dict) error:NULL];
}

static void AssertCalendarDay(NSDate *date, NSInteger year, NSInteger month, NSInteger day) {
    XCTAssertNotNil(date);
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *c = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                      fromDate:date];
    XCTAssertEqual(c.year, year);
    XCTAssertEqual(c.month, month);
    XCTAssertEqual(c.day, day);
}

- (void)testManifestWithoutNotesParsesExactlyAsBefore {
    CDRManifest *m = ManifestWith(@{});
    XCTAssertNotNil(m);
    XCTAssertEqualObjects(m.advertisedRelease.version, @"1.1");
    XCTAssertEqual(m.advertisedRelease.notes.count, 0u);
    XCTAssertEqual(m.advertisedRelease.undisplayableNoteCount, 0u);
    XCTAssertNil(m.advertisedRelease.date);
    XCTAssertEqual(m.history.count, 0u);
    XCTAssertNil(m.artifactSize);
    XCTAssertEqual(m.parseWarnings.count, 0u);
}

- (void)testAllSevenDeveloperTypesParseToTheirEnumValues {
    NSArray<NSString *> *keys = @[@"fixed", @"improved", @"added", @"security",
                                  @"disabled", @"removed", @"notice"];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in keys) [items addObject:Note(key, [key stringByAppendingString:@" text"])];
    CDRManifest *m = ManifestWith(@{@"notes": items});

    XCTAssertEqual(m.advertisedRelease.notes.count, 7u);
    XCTAssertEqual(m.parseWarnings.count, 0u);
    // Manifest order is preserved on the flat list…
    for (NSUInteger i = 0; i < keys.count; i++) {
        CDRReleaseNote *note = m.advertisedRelease.notes[i];
        XCTAssertEqualObjects(CDRReleaseNoteTypeKey(note.type), keys[i]);
        XCTAssertEqualObjects(note.text, [keys[i] stringByAppendingString:@" text"]);
    }
    // …and the groups come out in the fixed order regardless.
    NSArray<NSNumber *> *groupTypes = [m.advertisedRelease.groups valueForKey:@"type"];
    XCTAssertEqualObjects(groupTypes, (@[@(CDRReleaseNoteTypeNotice), @(CDRReleaseNoteTypeRemoved),
                                         @(CDRReleaseNoteTypeDisabled), @(CDRReleaseNoteTypeSecurity),
                                         @(CDRReleaseNoteTypeAdded), @(CDRReleaseNoteTypeImproved),
                                         @(CDRReleaseNoteTypeFixed)]));
    XCTAssertEqual(m.advertisedRelease.typeSet, CDRReleaseNoteTypeSetDeveloperAuthored);
}

- (void)testUnknownTypeIsDroppedLoggedAndCounted {
    CDRManifest *m = ManifestWith(@{@"notes": @[
        Note(@"added", @"kept"),
        Note(@"deprecated", @"from a newer vocabulary"),
        Note(@"fixed", @"also kept"),
    ]});
    XCTAssertNotNil(m);
    XCTAssertEqualObjects([m.advertisedRelease.notes valueForKey:@"text"], (@[@"kept", @"also kept"]));
    XCTAssertEqual(m.advertisedRelease.undisplayableNoteCount, 1u);
    XCTAssertEqual(m.parseWarnings.count, 1u);
    XCTAssertTrue([m.parseWarnings.firstObject containsString:@"deprecated"]);
    // The rest of the manifest is unaffected.
    XCTAssertEqualObjects(m.version, @"1.1");
    XCTAssertEqualObjects(m.artifactURL.absoluteString, @"https://example.com/app-1.1.dmg");
}

- (void)testRetractedFromAManifestIsDroppedNeverRendered {
    CDRManifest *m = ManifestWith(@{@"notes": @[
        Note(@"retracted", @"forged: pretend the developer pulled something"),
        Note(@"improved", @"real"),
    ]});
    XCTAssertEqual(m.advertisedRelease.notes.count, 1u);
    XCTAssertEqual(m.advertisedRelease.notes.firstObject.type, CDRReleaseNoteTypeImproved);
    XCTAssertFalse(CDRReleaseNoteTypeSetContains(m.advertisedRelease.typeSet, CDRReleaseNoteTypeRetracted));
    XCTAssertEqual(m.advertisedRelease.undisplayableNoteCount, 1u);
    XCTAssertEqual(m.parseWarnings.count, 1u);
    XCTAssertTrue([m.parseWarnings.firstObject containsString:@"retracted"]);
}

- (void)testMalformedNoteItemsAreDroppedWithoutBeingCounted {
    CDRManifest *m = ManifestWith(@{@"notes": @[
        @"just a string",
        @{@"text": @"no type"},
        @{@"type": @"added"},
        @{@"type": @"added", @"text": @"   "},
        @{@"type": @"added", @"text": @42},
        Note(@"added", @"the only good one"),
    ]});
    XCTAssertNotNil(m);
    XCTAssertEqualObjects([m.advertisedRelease.notes valueForKey:@"text"], (@[@"the only good one"]));
    // Nothing nameable was said by the malformed items, so nothing is counted.
    XCTAssertEqual(m.advertisedRelease.undisplayableNoteCount, 0u);
    XCTAssertEqual(m.parseWarnings.count, 5u);
}

- (void)testNotesThatAreNotAnArrayNeverFailTheManifest {
    for (id bad in @[@"notes as a string", @{@"type": @"added"}, @7]) {
        CDRManifest *m = ManifestWith(@{@"notes": bad, @"history": bad});
        XCTAssertNotNil(m, @"display data must never fail a manifest");
        XCTAssertEqual(m.advertisedRelease.notes.count, 0u);
        XCTAssertEqual(m.history.count, 0u);
        XCTAssertEqual(m.parseWarnings.count, 2u);
    }
}

- (void)testNoteTextIsSanitizedAndLongTextTruncatedWithAWarning {
    NSString *longText = [@"" stringByPaddingToLength:CDRReleaseNoteMaxTextLength + 100
                                           withString:@"word " startingAtIndex:0];
    CDRManifest *m = ManifestWith(@{@"notes": @[
        Note(@"fixed", @"  Scrubbing\nno longer   skips. "),
        Note(@"fixed", longText),
    ]});
    XCTAssertEqualObjects(m.advertisedRelease.notes[0].text, @"Scrubbing no longer skips.");
    XCTAssertLessThanOrEqual(m.advertisedRelease.notes[1].text.length, CDRReleaseNoteMaxTextLength);
    XCTAssertEqual(m.parseWarnings.count, 1u);
    XCTAssertTrue([m.parseWarnings.firstObject containsString:@"truncated"]);
}

- (void)testNotesBeyondThePerReleaseCapAreIgnored {
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < CDRManifestMaxNotesPerRelease + 5; i++) {
        [items addObject:Note(@"fixed", [NSString stringWithFormat:@"fix %lu", (unsigned long)i])];
    }
    CDRManifest *m = ManifestWith(@{@"notes": items});
    XCTAssertEqual(m.advertisedRelease.notes.count, CDRManifestMaxNotesPerRelease);
    XCTAssertEqual(m.parseWarnings.count, 1u);
}

- (void)testReleasedDateAndSize {
    CDRManifest *m = ManifestWith(@{@"released": @"2026-11-03", @"size": @19293798});
    AssertCalendarDay(m.advertisedRelease.date, 2026, 11, 3);
    XCTAssertEqualObjects(m.artifactSize, @19293798);
    XCTAssertEqual(m.parseWarnings.count, 0u);
}

- (void)testInvalidReleasedDateAndSizeAreIgnoredWithWarnings {
    for (id bad in @[@"Nov 3, 2026", @"2026-02-31", @"2026-13-01", @"2026-11-3", @"20261103", @20261103]) {
        CDRManifest *m = ManifestWith(@{@"released": bad});
        XCTAssertNotNil(m);
        XCTAssertNil(m.advertisedRelease.date, @"%@ is not a calendar day", bad);
        XCTAssertEqual(m.parseWarnings.count, 1u);
    }
    for (id bad in @[@0, @-5, @"18.4 MB", @YES]) {
        CDRManifest *m = ManifestWith(@{@"size": bad});
        XCTAssertNotNil(m);
        XCTAssertNil(m.artifactSize, @"%@ is not a byte count", bad);
        XCTAssertEqual(m.parseWarnings.count, 1u);
    }
}

#pragma mark - History

static NSDictionary *HistoryEntry(NSString *version, NSString *date, NSArray *notes) {
    NSMutableDictionary *entry = [@{@"version": version} mutableCopy];
    if (date) entry[@"date"] = date;
    if (notes) entry[@"notes"] = notes;
    return entry;
}

- (void)testSkippedVersionHistoryResolvesBetweenInstalledAndAdvertised {
    // Advertised 1.4; the user has 1.2. Only 1.3 sits strictly between.
    CDRManifest *m = ManifestWith(@{
        @"version": @"1.4",
        @"notes": @[Note(@"notice", @"1.4 notice")],
        @"history": @[
            HistoryEntry(@"1.3", @"2026-10-14", @[Note(@"added", @"1.3 added"), Note(@"fixed", @"1.3 fixed")]),
            HistoryEntry(@"1.2", @"2026-09-01", @[Note(@"fixed", @"1.2 fixed")]),
            HistoryEntry(@"1.1", nil, @[Note(@"fixed", @"1.1 fixed")]),
        ],
    });
    XCTAssertEqual(m.history.count, 3u, @"history is kept as served");

    NSArray<CDRRelease *> *releases = [m releasesNewerThanVersion:@"1.2"];
    XCTAssertEqualObjects([releases valueForKey:@"version"], (@[@"1.4", @"1.3"]));
    XCTAssertTrue(releases.firstObject == m.advertisedRelease);
    AssertCalendarDay(releases[1].date, 2026, 10, 14);
    XCTAssertEqual(releases[1].notes.count, 2u);
    XCTAssertEqual(releases[1].typeSet, CDRReleaseNoteTypeSetAdded | CDRReleaseNoteTypeSetFixed);
}

- (void)testHistoryEntriesAtOrBelowInstalledAreIgnored {
    CDRManifest *m = ManifestWith(@{
        @"version": @"1.4",
        @"history": @[HistoryEntry(@"1.3", nil, nil), HistoryEntry(@"1.2", nil, nil),
                      HistoryEntry(@"1.0", nil, nil)],
    });
    XCTAssertEqualObjects([[m releasesNewerThanVersion:@"1.3"] valueForKey:@"version"], (@[@"1.4"]));
    XCTAssertEqualObjects([[m releasesNewerThanVersion:@"1.2.0"] valueForKey:@"version"], (@[@"1.4", @"1.3"]));
    XCTAssertEqualObjects([[m releasesNewerThanVersion:@"0.9"] valueForKey:@"version"],
                          (@[@"1.4", @"1.3", @"1.2", @"1.0"]));
}

- (void)testHistoryEntriesAtOrAboveAdvertisedAreIgnored {
    // Top-level `notes` is the only home for the advertised version's notes,
    // and history can never smuggle in a version that isn't installable.
    CDRManifest *m = ManifestWith(@{
        @"version": @"1.4",
        @"notes": @[Note(@"added", @"the real 1.4 note")],
        @"history": @[
            HistoryEntry(@"2.0", nil, @[Note(@"notice", @"from the future")]),
            HistoryEntry(@"1.4", nil, @[Note(@"removed", @"a second opinion on 1.4")]),
            HistoryEntry(@"1.4.0", nil, nil),
            HistoryEntry(@"1.3", nil, nil),
        ],
    });
    NSArray<CDRRelease *> *releases = [m releasesNewerThanVersion:@"1.0"];
    XCTAssertEqualObjects([releases valueForKey:@"version"], (@[@"1.4", @"1.3"]));
    XCTAssertEqualObjects(releases.firstObject.notes.firstObject.text, @"the real 1.4 note");
}

- (void)testHistoryIsSortedNewestFirstAndDeduplicated {
    CDRManifest *m = ManifestWith(@{
        @"version": @"2.0",
        @"history": @[
            HistoryEntry(@"1.2", nil, nil),
            HistoryEntry(@"1.10", nil, @[Note(@"fixed", @"first 1.10")]),
            HistoryEntry(@"1.9", nil, nil),
            HistoryEntry(@"1.10.0", nil, @[Note(@"fixed", @"duplicate 1.10")]),
        ],
    });
    NSArray<CDRRelease *> *releases = [m releasesNewerThanVersion:@"1.0"];
    XCTAssertEqualObjects([releases valueForKey:@"version"], (@[@"2.0", @"1.10", @"1.9", @"1.2"]));
    XCTAssertEqualObjects(releases[1].notes.firstObject.text, @"first 1.10", @"first entry wins");
}

- (void)testNothingIsReturnedWhenTheAdvertisedVersionIsNotNewer {
    CDRManifest *m = ManifestWith(@{
        @"version": @"1.4",
        @"notes": @[Note(@"added", @"x")],
        @"history": @[HistoryEntry(@"1.3", nil, nil)],
    });
    XCTAssertEqual([m releasesNewerThanVersion:@"1.4"].count, 0u);
    XCTAssertEqual([m releasesNewerThanVersion:@"2.0"].count, 0u);
}

- (void)testHistoryIsCappedAndMalformedEntriesDropped {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSUInteger i = 0; i < CDRManifestMaxHistoryEntries + 4; i++) {
        [entries addObject:HistoryEntry([NSString stringWithFormat:@"1.%lu", (unsigned long)(50 - i)], nil, nil)];
    }
    CDRManifest *capped = ManifestWith(@{@"version": @"2.0", @"history": entries});
    XCTAssertEqual(capped.history.count, CDRManifestMaxHistoryEntries);
    XCTAssertEqual(capped.parseWarnings.count, 1u);

    CDRManifest *malformed = ManifestWith(@{@"version": @"2.0", @"history": @[
        @"1.5",
        @{@"date": @"2026-01-01"},
        @{@"version": @""},
        HistoryEntry(@"1.5", @"yesterday", @[Note(@"mystery", @"?"), Note(@"fixed", @"ok")]),
    ]});
    XCTAssertEqual(malformed.history.count, 1u);
    XCTAssertNil(malformed.history.firstObject.date);
    XCTAssertEqual(malformed.history.firstObject.notes.count, 1u);
    XCTAssertEqual(malformed.history.firstObject.undisplayableNoteCount, 1u);
    // 3 dropped entries + the bad date + the unknown type.
    XCTAssertEqual(malformed.parseWarnings.count, 5u);
}

@end
