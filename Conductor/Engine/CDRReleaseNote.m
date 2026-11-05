//
//  CDRReleaseNote.m
//  Conductor
//

#import "CDRReleaseNote.h"

const NSInteger CDRReleaseNoteTypeCount = CDRReleaseNoteTypeRetracted + 1;
const NSUInteger CDRReleaseNoteMaxTextLength = 500;

CDRReleaseNoteTypeSet CDRReleaseNoteTypeSetWithType(CDRReleaseNoteType type) {
    if (type < 0 || type >= CDRReleaseNoteTypeCount) return CDRReleaseNoteTypeSetNone;
    return (CDRReleaseNoteTypeSet)(1u << type);
}

BOOL CDRReleaseNoteTypeSetContains(CDRReleaseNoteTypeSet set, CDRReleaseNoteType type) {
    return (set & CDRReleaseNoteTypeSetWithType(type)) != 0;
}

NSString *CDRReleaseNoteTypeKey(CDRReleaseNoteType type) {
    switch (type) {
        case CDRReleaseNoteTypeNotice: return @"notice";
        case CDRReleaseNoteTypeRemoved: return @"removed";
        case CDRReleaseNoteTypeDisabled: return @"disabled";
        case CDRReleaseNoteTypeSecurity: return @"security";
        case CDRReleaseNoteTypeAdded: return @"added";
        case CDRReleaseNoteTypeImproved: return @"improved";
        case CDRReleaseNoteTypeFixed: return @"fixed";
        case CDRReleaseNoteTypeRetracted: return @"retracted";
    }
    return @"";
}

BOOL CDRReleaseNoteTypeFromKey(NSString *key, CDRReleaseNoteType *outType) {
    if (![key isKindOfClass:[NSString class]]) return NO;
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        if ([key isEqualToString:CDRReleaseNoteTypeKey((CDRReleaseNoteType)i)]) {
            if (outType) *outType = (CDRReleaseNoteType)i;
            return YES;
        }
    }
    return NO;
}

NSString *CDRReleaseNoteTypeDisplayName(CDRReleaseNoteType type) {
    switch (type) {
        case CDRReleaseNoteTypeNotice: return @"Notice";
        case CDRReleaseNoteTypeRemoved: return @"Removed";
        case CDRReleaseNoteTypeDisabled: return @"Disabled";
        case CDRReleaseNoteTypeSecurity: return @"Security";
        case CDRReleaseNoteTypeAdded: return @"Added";
        case CDRReleaseNoteTypeImproved: return @"Improved";
        case CDRReleaseNoteTypeFixed: return @"Fixed";
        case CDRReleaseNoteTypeRetracted: return @"Retracted";
    }
    return @"";
}

NSString *CDRReleaseNoteTypeNounPhrase(CDRReleaseNoteType type) {
    switch (type) {
        case CDRReleaseNoteTypeNotice: return @"a notice";
        case CDRReleaseNoteTypeRemoved: return @"a removal";
        case CDRReleaseNoteTypeDisabled: return @"a disabled feature";
        case CDRReleaseNoteTypeSecurity: return @"a security fix";
        case CDRReleaseNoteTypeAdded: return @"an addition";
        case CDRReleaseNoteTypeImproved: return @"an improvement";
        case CDRReleaseNoteTypeFixed: return @"a fix";
        case CDRReleaseNoteTypeRetracted: return @"a retraction";
    }
    return @"";
}

NSString *CDRReleaseNoteTypeCountPhrase(CDRReleaseNoteType type, NSUInteger count) {
    NSString *singular = @"note", *plural = @"notes";
    switch (type) {
        case CDRReleaseNoteTypeNotice: singular = @"notice"; plural = @"notices"; break;
        case CDRReleaseNoteTypeRemoved: singular = @"removal"; plural = @"removals"; break;
        case CDRReleaseNoteTypeDisabled: singular = @"disabled feature"; plural = @"disabled features"; break;
        case CDRReleaseNoteTypeSecurity: singular = @"security fix"; plural = @"security fixes"; break;
        case CDRReleaseNoteTypeAdded: singular = @"addition"; plural = @"additions"; break;
        case CDRReleaseNoteTypeImproved: singular = @"improvement"; plural = @"improvements"; break;
        case CDRReleaseNoteTypeFixed: singular = @"fix"; plural = @"fixes"; break;
        case CDRReleaseNoteTypeRetracted: singular = @"retraction"; plural = @"retractions"; break;
    }
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)count, count == 1 ? singular : plural];
}

BOOL CDRReleaseNoteTypeIsDeveloperAuthored(CDRReleaseNoteType type) {
    return type >= CDRReleaseNoteTypeNotice && type < CDRReleaseNoteTypeRetracted;
}

NSString *CDRSanitizedReleaseNoteText(id raw, BOOL *outTruncated) {
    if (outTruncated) *outTruncated = NO;
    if (![raw isKindOfClass:[NSString class]]) return nil;

    static NSCharacterSet *separators;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
        [set formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
        separators = [set copy];
    });

    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *part in [(NSString *)raw componentsSeparatedByCharactersInSet:separators]) {
        if (part.length > 0) [words addObject:part];
    }
    NSString *text = [words componentsJoinedByString:@" "];
    if (text.length == 0) return nil;

    if (text.length > CDRReleaseNoteMaxTextLength) {
        // Cut on a composed-character boundary so an emoji or accented
        // character is never split, leaving room for the ellipsis.
        const NSUInteger budget = CDRReleaseNoteMaxTextLength - 1;
        __block NSUInteger keepLength = 0;
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                                 options:NSStringEnumerationByComposedCharacterSequences
                                         | NSStringEnumerationSubstringNotRequired
                              usingBlock:^(NSString *substring, NSRange range, NSRange enclosing, BOOL *stop) {
            if (NSMaxRange(range) > budget) {
                *stop = YES;
                return;
            }
            keepLength = NSMaxRange(range);
        }];
        NSString *head = [[text substringToIndex:keepLength]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        text = [head stringByAppendingString:@"…"];
        if (outTruncated) *outTruncated = YES;
    }
    return text;
}

#pragma mark - CDRReleaseNote

@implementation CDRReleaseNote

+ (instancetype)noteWithType:(CDRReleaseNoteType)type text:(NSString *)text {
    CDRReleaseNote *note = [[CDRReleaseNote alloc] initPrivate];
    note->_type = type;
    note->_text = [text copy];
    return note;
}

- (instancetype)initPrivate {
    return [super init];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CDRReleaseNote class]]) return NO;
    CDRReleaseNote *other = object;
    return self.type == other.type && [self.text isEqualToString:other.text];
}

- (NSUInteger)hash {
    return self.text.hash ^ (NSUInteger)self.type;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@>", CDRReleaseNoteTypeKey(self.type), self.text];
}

@end

#pragma mark - CDRReleaseNoteGroup

@implementation CDRReleaseNoteGroup

- (instancetype)initWithType:(CDRReleaseNoteType)type notes:(NSArray<CDRReleaseNote *> *)notes {
    self = [super init];
    if (!self) return nil;
    _type = type;
    _notes = [notes copy];
    return self;
}

@end

NSArray<CDRReleaseNoteGroup *> *CDRGroupReleaseNotes(NSArray<CDRReleaseNote *> *notes) {
    NSMutableArray<CDRReleaseNoteGroup *> *groups = [NSMutableArray array];
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)i;
        NSMutableArray<CDRReleaseNote *> *members = [NSMutableArray array];
        for (CDRReleaseNote *note in notes) {
            if (note.type == type) [members addObject:note];
        }
        if (members.count > 0) {
            [groups addObject:[[CDRReleaseNoteGroup alloc] initWithType:type notes:members]];
        }
    }
    return groups;
}

#pragma mark - CDRRelease

@implementation CDRRelease

- (instancetype)initWithVersion:(NSString *)version
                           date:(NSDate *)date
                          notes:(NSArray<CDRReleaseNote *> *)notes
         undisplayableNoteCount:(NSUInteger)undisplayableNoteCount {
    self = [super init];
    if (!self) return nil;
    _version = [version copy];
    _date = date;
    _notes = [notes copy];
    _undisplayableNoteCount = undisplayableNoteCount;
    return self;
}

- (NSArray<CDRReleaseNoteGroup *> *)groups {
    return CDRGroupReleaseNotes(self.notes);
}

- (CDRReleaseNoteTypeSet)typeSet {
    CDRReleaseNoteTypeSet set = CDRReleaseNoteTypeSetNone;
    for (CDRReleaseNote *note in self.notes) set |= CDRReleaseNoteTypeSetWithType(note.type);
    return set;
}

@end
