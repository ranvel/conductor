//
//  CDRInterruptSheetModel.h
//  Conductor
//
//  What an interrupt sheet says, as a value. Pure — no AppKit — so the
//  wording and the "which button is default" rule are tested without a view.
//

#import <Foundation/Foundation.h>
#import "CDRReleaseNote.h"

NS_ASSUME_NONNULL_BEGIN

/// The four moments Conductor stops the user. One component, four variants,
/// so a user who has seen one recognizes the next.
typedef NS_ENUM(NSInteger, CDRInterruptSheetKind) {
    CDRInterruptSheetKindHeld = 0,
    CDRInterruptSheetKindRetraction,
    CDRInterruptSheetKindNetworkWithPolicy,
    CDRInterruptSheetKindNetworkNoPolicy,
};

/// What the user chose.
typedef NS_ENUM(NSInteger, CDRInterruptSheetResponse) {
    /// The quiet way out: Not now / Skip this version / Approve anyway.
    CDRInterruptSheetResponseSecondary = 0,
    /// The default button (Return): Install / OK / Approve and update / Skip this version.
    CDRInterruptSheetResponseDefault,
    /// The inline link ("Change in Settings"). Dismisses the sheet.
    CDRInterruptSheetResponseLink,
};

/// What pressing a button means, independent of which side it is on.
typedef NS_ENUM(NSInteger, CDRInterruptSheetAction) {
    CDRInterruptSheetActionDismiss = 0,   // Not now, OK
    CDRInterruptSheetActionInstall,       // Install, Approve and update, Approve anyway
    CDRInterruptSheetActionSkipVersion,   // Skip this version
};

@interface CDRInterruptSheetButton : NSObject
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) CDRInterruptSheetAction action;
+ (instancetype)buttonWithTitle:(NSString *)title action:(CDRInterruptSheetAction)action;
@end

/// One line of an entitlements diff: "+ com.apple.security.network.client".
@interface CDRInterruptSheetDiffLine : NSObject
@property (nonatomic, readonly) BOOL added;   // NO = removed
@property (nonatomic, readonly, copy) NSString *text;
+ (instancetype)lineWithText:(NSString *)text added:(BOOL)added;
@end

/// One row of the Internet Access Policy table: where, and why.
@interface CDRInterruptSheetPolicyRow : NSObject
@property (nonatomic, readonly, copy) NSString *subject;   // "search.example.com", "Any feed you add"
@property (nonatomic, readonly, copy) NSString *purpose;
+ (instancetype)rowWithSubject:(NSString *)subject purpose:(NSString *)purpose;
@end

@interface CDRInterruptSheetModel : NSObject

@property (nonatomic, readonly) CDRInterruptSheetKind kind;
@property (nonatomic, readonly, copy) NSString *appName;
@property (nonatomic, readonly, nullable) NSURL *appURL;

/// The header. `attentionHeader` draws it as the amber banner (retraction).
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *subtitle;
@property (nonatomic, readonly) BOOL attentionHeader;

/// One line of plain explanation under the header; `bodyEmphasis` is the
/// leading part drawn bold (the app's name).
@property (nonatomic, readonly, copy, nullable) NSString *body;
@property (nonatomic, readonly, copy, nullable) NSString *bodyEmphasis;

/// The notes that caused a hold, grouped and badged.
@property (nonatomic, readonly, copy, nullable) NSArray<CDRReleaseNoteGroup *> *noteGroups;
/// "You hold updates that include … items." and its link's title.
@property (nonatomic, readonly, copy, nullable) NSString *footnote;
@property (nonatomic, readonly, copy, nullable) NSString *linkTitle;

/// "ENTITLEMENTS · 0.4 → 0.5" and its lines (monospace block).
@property (nonatomic, readonly, copy, nullable) NSString *diffHeading;
@property (nonatomic, readonly, copy, nullable) NSArray<CDRInterruptSheetDiffLine *> *diffLines;
/// The developer's Internet Access Policy, as a two-column table.
@property (nonatomic, readonly, copy, nullable) NSArray<CDRInterruptSheetPolicyRow *> *policyRows;
/// The amber strip ("This build ships no Internet Access Policy.").
@property (nonatomic, readonly, copy, nullable) NSString *warning;

/// Nil for a one-button sheet (retraction).
@property (nonatomic, readonly, nullable) CDRInterruptSheetButton *secondaryButton;
/// The safe choice. Return activates it; Escape activates the secondary
/// button (or this one, when it is the only button).
@property (nonatomic, readonly) CDRInterruptSheetButton *defaultButton;

/// The action behind a response.
- (CDRInterruptSheetAction)actionForResponse:(CDRInterruptSheetResponse)response;

#pragma mark Variants

/// "SmoothMove 1.4 is waiting for you / Held because it includes a removal."
/// `heldGroups` are the offending notes; `holdTypes` the user's categories.
/// Install is the default: the user already chose to open this.
+ (instancetype)heldModelForAppNamed:(NSString *)appName
                              appURL:(nullable NSURL *)appURL
                             version:(NSString *)version
                          heldGroups:(NSArray<CDRReleaseNoteGroup *> *)heldGroups
                           holdTypes:(CDRReleaseNoteTypeSet)holdTypes;

/// "Developer retracted 1.2 / You have the latest build." One button: OK.
+ (instancetype)retractionModelForAppNamed:(NSString *)appName
                                    appURL:(nullable NSURL *)appURL
                          retractedVersion:(NSString *)retractedVersion
                          installedVersion:(NSString *)installedVersion;

/// The new build gains internet access. With `policyRows` the developer says
/// where it connects and why, and Approve is the default; with nil it
/// doesn't, the amber strip says so, and Skip is the default.
+ (instancetype)networkModelForAppNamed:(NSString *)appName
                                 appURL:(nullable NSURL *)appURL
                            fromVersion:(NSString *)fromVersion
                              toVersion:(NSString *)toVersion
                              diffLines:(NSArray<CDRInterruptSheetDiffLine *> *)diffLines
                             policyRows:(nullable NSArray<CDRInterruptSheetPolicyRow *> *)policyRows;

@end

/// The notes of the given releases whose type is in `types`, grouped in the
/// fixed order — what a held sheet shows.
NSArray<CDRReleaseNoteGroup *> *CDRNoteGroupsOfTypes(NSArray<CDRRelease *> *releases, CDRReleaseNoteTypeSet types);

/// "Notice, Removed or Retracted" — a type set as an either/or list.
NSString *CDRReleaseNoteTypeSetOrList(CDRReleaseNoteTypeSet set);

NS_ASSUME_NONNULL_END
