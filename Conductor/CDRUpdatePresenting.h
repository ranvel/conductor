//
//  CDRUpdatePresenting.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import "CDRManifest.h"
#import "CDRUpdateOperation.h"

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

/// The last-moment re-check refused a retracted update the user tried to
/// install (retraction State A at install time).
- (void)presentRetractionNotice:(NSString *)message vendorURL:(nullable NSURL *)vendorURL;

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
