//
//  CDRInterruptSheetModel.m
//  Conductor
//

#import "CDRInterruptSheetModel.h"

@implementation CDRInterruptSheetButton
+ (instancetype)buttonWithTitle:(NSString *)title action:(CDRInterruptSheetAction)action {
    CDRInterruptSheetButton *button = [[CDRInterruptSheetButton alloc] init];
    button->_title = [title copy];
    button->_action = action;
    return button;
}
@end

@implementation CDRInterruptSheetDiffLine
+ (instancetype)lineWithText:(NSString *)text added:(BOOL)added {
    CDRInterruptSheetDiffLine *line = [[CDRInterruptSheetDiffLine alloc] init];
    line->_text = [text copy];
    line->_added = added;
    return line;
}
@end

@implementation CDRInterruptSheetPolicyRow
+ (instancetype)rowWithSubject:(NSString *)subject purpose:(NSString *)purpose {
    CDRInterruptSheetPolicyRow *row = [[CDRInterruptSheetPolicyRow alloc] init];
    row->_subject = [subject copy];
    row->_purpose = [purpose copy];
    return row;
}
@end

NSArray<CDRReleaseNoteGroup *> *CDRNoteGroupsOfTypes(NSArray<CDRRelease *> *releases, CDRReleaseNoteTypeSet types) {
    NSMutableArray<CDRReleaseNote *> *notes = [NSMutableArray array];
    for (CDRRelease *release in releases) {
        for (CDRReleaseNote *note in release.notes) {
            if (CDRReleaseNoteTypeSetContains(types, note.type)) [notes addObject:note];
        }
    }
    return CDRGroupReleaseNotes(notes);
}

NSString *CDRReleaseNoteTypeSetOrList(CDRReleaseNoteTypeSet set) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        if (CDRReleaseNoteTypeSetContains(set, (CDRReleaseNoteType)i)) {
            [names addObject:CDRReleaseNoteTypeDisplayName((CDRReleaseNoteType)i)];
        }
    }
    if (names.count <= 1) return names.firstObject ?: @"";
    NSArray<NSString *> *head = [names subarrayWithRange:NSMakeRange(0, names.count - 1)];
    return [NSString stringWithFormat:@"%@ or %@", [head componentsJoinedByString:@", "], names.lastObject];
}

@interface CDRInterruptSheetModel ()
@property (nonatomic, readwrite) CDRInterruptSheetKind kind;
@property (nonatomic, readwrite, copy) NSString *appName;
@property (nonatomic, readwrite, nullable) NSURL *appURL;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *subtitle;
@property (nonatomic, readwrite) BOOL attentionHeader;
@property (nonatomic, readwrite, copy, nullable) NSString *body;
@property (nonatomic, readwrite, copy, nullable) NSString *bodyEmphasis;
@property (nonatomic, readwrite, copy, nullable) NSArray<CDRReleaseNoteGroup *> *noteGroups;
@property (nonatomic, readwrite, copy, nullable) NSString *footnote;
@property (nonatomic, readwrite, copy, nullable) NSString *linkTitle;
@property (nonatomic, readwrite, copy, nullable) NSString *diffHeading;
@property (nonatomic, readwrite, copy, nullable) NSArray<CDRInterruptSheetDiffLine *> *diffLines;
@property (nonatomic, readwrite, copy, nullable) NSArray<CDRInterruptSheetPolicyRow *> *policyRows;
@property (nonatomic, readwrite, copy, nullable) NSString *warning;
@property (nonatomic, readwrite, nullable) CDRInterruptSheetButton *secondaryButton;
@property (nonatomic, readwrite) CDRInterruptSheetButton *defaultButton;
@end

@implementation CDRInterruptSheetModel

- (CDRInterruptSheetAction)actionForResponse:(CDRInterruptSheetResponse)response {
    switch (response) {
        case CDRInterruptSheetResponseDefault:
            return self.defaultButton.action;
        case CDRInterruptSheetResponseSecondary:
            // Escape on a one-button sheet is that button.
            return self.secondaryButton ? self.secondaryButton.action : self.defaultButton.action;
        case CDRInterruptSheetResponseLink:
            return CDRInterruptSheetActionDismiss;
    }
    return CDRInterruptSheetActionDismiss;
}

+ (instancetype)heldModelForAppNamed:(NSString *)appName
                              appURL:(NSURL *)appURL
                             version:(NSString *)version
                          heldGroups:(NSArray<CDRReleaseNoteGroup *> *)heldGroups
                           holdTypes:(CDRReleaseNoteTypeSet)holdTypes {
    CDRInterruptSheetModel *model = [[CDRInterruptSheetModel alloc] init];
    model.kind = CDRInterruptSheetKindHeld;
    model.appName = appName;
    model.appURL = appURL;
    model.title = [NSString stringWithFormat:@"%@ %@ is waiting for you", appName, version];
    // Name the first held category in the fixed order.
    model.subtitle = heldGroups.count > 0
        ? [NSString stringWithFormat:@"Held because it includes %@.",
           CDRReleaseNoteTypeNounPhrase(heldGroups.firstObject.type)]
        : @"Held for manual install.";
    model.noteGroups = heldGroups;
    model.footnote = [NSString stringWithFormat:@"You hold updates that include %@ items.",
                      CDRReleaseNoteTypeSetOrList(holdTypes | CDRReleaseNoteTypeSetRetracted)];
    model.linkTitle = @"Change in Settings";
    model.secondaryButton = [CDRInterruptSheetButton buttonWithTitle:@"Not now"
                                                              action:CDRInterruptSheetActionDismiss];
    // The user already chose to open this: installing is what they came for.
    model.defaultButton = [CDRInterruptSheetButton buttonWithTitle:[NSString stringWithFormat:@"Install %@", version]
                                                            action:CDRInterruptSheetActionInstall];
    return model;
}

+ (instancetype)retractionModelForAppNamed:(NSString *)appName
                                    appURL:(NSURL *)appURL
                          retractedVersion:(NSString *)retractedVersion
                          installedVersion:(NSString *)installedVersion {
    CDRInterruptSheetModel *model = [[CDRInterruptSheetModel alloc] init];
    model.kind = CDRInterruptSheetKindRetraction;
    model.appName = appName;
    model.appURL = appURL;
    model.attentionHeader = YES;
    model.title = [NSString stringWithFormat:@"Developer retracted %@", retractedVersion];
    model.subtitle = @"You have the latest build.";
    model.bodyEmphasis = appName;
    model.body = [NSString stringWithFormat:
        @"%@ %@ was advertised, then pulled. %@ stays installed and nothing changes on your Mac.",
        appName, retractedVersion, installedVersion];
    model.defaultButton = [CDRInterruptSheetButton buttonWithTitle:@"OK" action:CDRInterruptSheetActionDismiss];
    return model;
}

+ (instancetype)networkModelForAppNamed:(NSString *)appName
                                 appURL:(NSURL *)appURL
                            fromVersion:(NSString *)fromVersion
                              toVersion:(NSString *)toVersion
                              diffLines:(NSArray<CDRInterruptSheetDiffLine *> *)diffLines
                             policyRows:(NSArray<CDRInterruptSheetPolicyRow *> *)policyRows {
    CDRInterruptSheetModel *model = [[CDRInterruptSheetModel alloc] init];
    model.appName = appName;
    model.appURL = appURL;
    model.subtitle = [NSString stringWithFormat:@"%@ made no connections.", fromVersion];
    model.diffHeading = [NSString stringWithFormat:@"ENTITLEMENTS · %@ → %@", fromVersion, toVersion];
    model.diffLines = diffLines;

    CDRInterruptSheetButton *skip = [CDRInterruptSheetButton buttonWithTitle:@"Skip this version"
                                                                      action:CDRInterruptSheetActionSkipVersion];
    if (policyRows.count > 0) {
        // The developer says where it connects and why: approving is the
        // informed, safe default.
        model.kind = CDRInterruptSheetKindNetworkWithPolicy;
        model.title = [NSString stringWithFormat:@"%@ %@ adds internet access", appName, toVersion];
        model.policyRows = policyRows;
        model.secondaryButton = skip;
        model.defaultButton = [CDRInterruptSheetButton buttonWithTitle:@"Approve and update"
                                                                action:CDRInterruptSheetActionInstall];
    } else {
        // No explanation: the safe default is not to take this build.
        model.kind = CDRInterruptSheetKindNetworkNoPolicy;
        model.title = [NSString stringWithFormat:@"%@ %@ wants internet access and doesn’t say why.",
                       appName, toVersion];
        model.warning = @"This build ships no Internet Access Policy.";
        model.secondaryButton = [CDRInterruptSheetButton buttonWithTitle:@"Approve anyway"
                                                                  action:CDRInterruptSheetActionInstall];
        model.defaultButton = skip;
    }
    return model;
}

@end
