//
//  CDRReleaseNoteTests.m
//  ConductorTests
//

#import <XCTest/XCTest.h>
#import "CDRReleaseNote.h"

@interface CDRReleaseNoteTests : XCTestCase
@end

@implementation CDRReleaseNoteTests

#pragma mark - Vocabulary

- (void)testEnumOrderIsTheFixedRenderOrder {
    // spec.md §3.5: what takes something away comes first. Sorting by type
    // relies on this order, so it is asserted rather than assumed.
    NSArray<NSString *> *expected = @[@"notice", @"removed", @"disabled", @"security",
                                      @"added", @"improved", @"fixed", @"retracted"];
    XCTAssertEqual(CDRReleaseNoteTypeCount, (NSInteger)expected.count);
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        XCTAssertEqualObjects(CDRReleaseNoteTypeKey((CDRReleaseNoteType)i), expected[i]);
    }
}

- (void)testKeyRoundTripsForEveryType {
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)i;
        CDRReleaseNoteType parsed = CDRReleaseNoteTypeFixed;
        XCTAssertTrue(CDRReleaseNoteTypeFromKey(CDRReleaseNoteTypeKey(type), &parsed));
        XCTAssertEqual(parsed, type);
        XCTAssertGreaterThan(CDRReleaseNoteTypeDisplayName(type).length, 0u);
    }
}

- (void)testUnknownKeysAreRejectedNeverGuessedAt {
    CDRReleaseNoteType type = CDRReleaseNoteTypeAdded;
    for (id key in @[@"deprecated", @"changed", @"Notice", @"FIXED", @" fixed", @"", @7, [NSNull null]]) {
        XCTAssertFalse(CDRReleaseNoteTypeFromKey(key, &type), @"%@ must not parse", key);
    }
    XCTAssertFalse(CDRReleaseNoteTypeFromKey(nil, &type));
    XCTAssertEqual(type, CDRReleaseNoteTypeAdded, @"out-param untouched on failure");
}

- (void)testOnlyRetractedIsNotDeveloperAuthored {
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)i;
        XCTAssertEqual(CDRReleaseNoteTypeIsDeveloperAuthored(type), type != CDRReleaseNoteTypeRetracted);
    }
}

- (void)testTypeSets {
    CDRReleaseNoteTypeSet set = CDRReleaseNoteTypeSetWithType(CDRReleaseNoteTypeRemoved)
        | CDRReleaseNoteTypeSetWithType(CDRReleaseNoteTypeFixed);
    XCTAssertEqual(set, CDRReleaseNoteTypeSetRemoved | CDRReleaseNoteTypeSetFixed);
    XCTAssertTrue(CDRReleaseNoteTypeSetContains(set, CDRReleaseNoteTypeRemoved));
    XCTAssertFalse(CDRReleaseNoteTypeSetContains(set, CDRReleaseNoteTypeNotice));

    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)i;
        XCTAssertTrue(CDRReleaseNoteTypeSetContains(CDRReleaseNoteTypeSetAll, type));
        XCTAssertEqual(CDRReleaseNoteTypeSetContains(CDRReleaseNoteTypeSetDeveloperAuthored, type),
                       type != CDRReleaseNoteTypeRetracted);
    }
}

#pragma mark - Plain-text rule

- (void)testTextIsTrimmedAndWhitespaceCollapsed {
    BOOL truncated = YES;
    NSString *text = CDRSanitizedReleaseNoteText(@"  Pin any\twave\n\nto   the sidebar. \r\n", &truncated);
    XCTAssertEqualObjects(text, @"Pin any wave to the sidebar.");
    XCTAssertFalse(truncated);
}

- (void)testEmptyOrNonStringTextIsRefused {
    for (id raw in @[@"", @"   \n\t ", @42, @[@"a"], [NSNull null]]) {
        XCTAssertNil(CDRSanitizedReleaseNoteText(raw, NULL), @"%@ must not produce text", raw);
    }
    XCTAssertNil(CDRSanitizedReleaseNoteText(nil, NULL));
}

- (void)testMarkupIsKeptAsLiteralText {
    // No markup is interpreted: what the developer typed is what is shown.
    NSString *raw = @"**Bold** [link](https://example.com) <b>tag</b>";
    XCTAssertEqualObjects(CDRSanitizedReleaseNoteText(raw, NULL), raw);
}

- (void)testLongTextIsCappedWithAnEllipsis {
    NSString *raw = [@"" stringByPaddingToLength:CDRReleaseNoteMaxTextLength + 40
                                      withString:@"abcdefghi " startingAtIndex:0];
    BOOL truncated = NO;
    NSString *text = CDRSanitizedReleaseNoteText(raw, &truncated);
    XCTAssertTrue(truncated);
    XCTAssertLessThanOrEqual(text.length, CDRReleaseNoteMaxTextLength);
    XCTAssertTrue([text hasSuffix:@"…"]);

    NSString *exact = [@"" stringByPaddingToLength:CDRReleaseNoteMaxTextLength
                                        withString:@"x" startingAtIndex:0];
    XCTAssertEqualObjects(CDRSanitizedReleaseNoteText(exact, &truncated), exact);
    XCTAssertFalse(truncated);
}

- (void)testTruncationNeverSplitsAComposedCharacter {
    // Every "character" here is a surrogate pair; a naive cut at an odd
    // index would leave half an emoji.
    NSString *raw = [@"" stringByPaddingToLength:CDRReleaseNoteMaxTextLength * 2
                                      withString:@"🎵" startingAtIndex:0];
    NSString *text = CDRSanitizedReleaseNoteText(raw, NULL);
    XCTAssertLessThanOrEqual(text.length, CDRReleaseNoteMaxTextLength);
    NSString *body = [text substringToIndex:text.length - 1];
    XCTAssertEqual(body.length % 2, 0u);
    XCTAssertNotNil([body dataUsingEncoding:NSUTF8StringEncoding]);
}

#pragma mark - Grouping

- (void)testGroupingUsesTheFixedOrderRegardlessOfInputOrder {
    NSArray<CDRReleaseNote *> *notes = @[
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeFixed text:@"f1"],
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeAdded text:@"a1"],
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeNotice text:@"n1"],
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeFixed text:@"f2"],
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeRemoved text:@"r1"],
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeAdded text:@"a2"],
    ];
    NSArray<CDRReleaseNoteGroup *> *groups = CDRGroupReleaseNotes(notes);

    NSArray<NSNumber *> *types = [groups valueForKey:@"type"];
    XCTAssertEqualObjects(types, (@[@(CDRReleaseNoteTypeNotice), @(CDRReleaseNoteTypeRemoved),
                                    @(CDRReleaseNoteTypeAdded), @(CDRReleaseNoteTypeFixed)]));
    // Stable within a group: manifest order survives.
    XCTAssertEqualObjects([groups[2].notes valueForKey:@"text"], (@[@"a1", @"a2"]));
    XCTAssertEqualObjects([groups[3].notes valueForKey:@"text"], (@[@"f1", @"f2"]));
}

- (void)testGroupingEmptyNotesYieldsNoGroups {
    XCTAssertEqual(CDRGroupReleaseNotes(@[]).count, 0u);
}

- (void)testReleaseExposesGroupsAndTypeSet {
    CDRRelease *release = [[CDRRelease alloc] initWithVersion:@"1.4" date:nil notes:@[
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeImproved text:@"i"],
        [CDRReleaseNote noteWithType:CDRReleaseNoteTypeSecurity text:@"s"],
    ] undisplayableNoteCount:2];
    XCTAssertEqual(release.typeSet, CDRReleaseNoteTypeSetSecurity | CDRReleaseNoteTypeSetImproved);
    XCTAssertEqual(release.groups.count, 2u);
    XCTAssertEqual(release.groups.firstObject.type, CDRReleaseNoteTypeSecurity);
    XCTAssertEqual(release.undisplayableNoteCount, 2u);
}

@end
