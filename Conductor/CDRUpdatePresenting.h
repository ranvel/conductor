//
//  CDRUpdatePresenting.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRManifest.h"
#import "CDRUpdateOperation.h"

#import "CDRInterruptSheetModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The presentation seam between CDRUpdateController and the UI. Two groups:
///
/// present* — modal-permitted: these only ever fire inside a flow the user
/// started (install consent, break-through offer, a refusal of an action the
/// user just took), so an alert is acceptable.
///
/// notify* — passive surfaces: results of background/scheduled checks. These
/// must NEVER present a modal — menu/window state, badge, and user
/// notifications only.
@protocol CDRUpdatePresenting <NSObject>

/// The three-way prompt from replace-flow.md §4:
/// "Quit & Update" / "Update on Quit" / "Skip".
- (void)presentQuitDecisionForAppNamed:(NSString *)appName
                                 reply:(void (^)(CDRQuitDecision decision))reply;

- (void)presentDeferredOfferForAppNamed:(NSString *)appName
                                version:(NSString *)version
                          deferredUntil:(NSDate *)deferredUntil
                             completion:(void (^)(BOOL installAnyway))completion;

/// Retraction State A reaching the user inside a flow they started: an
/// install whose last-moment re-check found the update withdrawn, or a
/// check they asked for. The amber sheet when the main window is key;
/// otherwise the same passive notification a background check posts.
/// `acknowledged` is YES only when the user dismissed the sheet.
- (void)presentRetractionForAppNamed:(NSString *)appName
                            bundleID:(NSString *)bundleID
                              appURL:(nullable NSURL *)appURL
                    retractedVersion:(NSString *)retractedVersion
                    installedVersion:(NSString *)installedVersion
                             message:(NSString *)message
                           vendorURL:(nullable NSURL *)vendorURL
                          completion:(void (^)(BOOL acknowledged))completion;

/// The user chose to install an update they hold for manual install: show
/// what it contains and ask once more. `heldGroups` are the offending notes,
/// `holdTypes` the user's hold categories. `install` is YES only for the
/// sheet's Install button.
- (void)presentHeldUpdateForAppNamed:(NSString *)appName
                            bundleID:(NSString *)bundleID
                              appURL:(nullable NSURL *)appURL
                             version:(NSString *)version
                          heldGroups:(NSArray<CDRReleaseNoteGroup *> *)heldGroups
                           holdTypes:(CDRReleaseNoteTypeSet)holdTypes
                          completion:(void (^)(BOOL install))completion;

/// A verified new build gains internet access and the user approves that
/// first (CND-7 supplies the data). With `policyRows` the developer's
/// Internet Access Policy is shown and Approve is the default; without,
/// Skip is. `action` is what the user chose: install, skip this version, or
/// dismiss.
- (void)presentNetworkApprovalForAppNamed:(NSString *)appName
                                 bundleID:(NSString *)bundleID
                                   appURL:(nullable NSURL *)appURL
                              fromVersion:(NSString *)fromVersion
                                toVersion:(NSString *)toVersion
                                diffLines:(NSArray<CDRInterruptSheetDiffLine *> *)diffLines
                               policyRows:(nullable NSArray<CDRInterruptSheetPolicyRow *> *)policyRows
                               completion:(void (^)(CDRInterruptSheetAction action))completion;

- (void)presentRelaunchOfferForAppNamed:(NSString *)appName appURL:(NSURL *)appURL;

- (void)notifyUpdateAvailableForAppNamed:(NSString *)appName
                                bundleID:(NSString *)bundleID
                                 version:(NSString *)version
                                 urgency:(CDRUrgency)urgency;

/// A surfaced update that waits on the user: held for a manual install, or
/// stopped at a major version. Passive, and deliberately without an Install
/// action — a held update is installed from the window, never from a banner.
- (void)notifyUpdateNeedsAttentionForAppNamed:(NSString *)appName
                                     bundleID:(NSString *)bundleID
                                      version:(NSString *)version
                                       reason:(NSString *)reason;

/// Retraction State A discovered during a check (loud once; the state store
/// was already cleared by the decision).
- (void)notifyRetractedPending:(NSString *)message
                      bundleID:(NSString *)bundleID
                     vendorURL:(nullable NSURL *)vendorURL;

/// Retraction State B (recalled build installed). The controller calls this at
/// most once per launch per version.
- (void)notifyRetractedInstalled:(NSString *)message
                        bundleID:(NSString *)bundleID
                       vendorURL:(nullable NSURL *)vendorURL;

- (void)notifyInstallCompletedForAppNamed:(NSString *)appName
                                 bundleID:(NSString *)bundleID
                                  version:(nullable NSString *)version;

- (void)notifyInstallFailedForAppNamed:(NSString *)appName
                              bundleID:(NSString *)bundleID
                                 error:(NSError *)error
                             vendorURL:(nullable NSURL *)vendorURL;

@end

NS_ASSUME_NONNULL_END
