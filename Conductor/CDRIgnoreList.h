//
//  CDRIgnoreList.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults key holding the ignored bundle IDs (array of strings). The
/// one source of truth for menu, window, and Settings. Ignored apps are
/// excluded from passive checks and the badge but stay visible in the UI with
/// an unignore affordance; a per-app manual check still works (user intent
/// overrides ignore).
extern NSString * const CDRIgnoredBundleIDsDefaultsKey;

NSSet<NSString *> *CDRIgnoredBundleIDs(NSUserDefaults *defaults);
void CDRSetBundleIDIgnored(NSString *bundleID, BOOL ignored, NSUserDefaults *defaults);

NS_ASSUME_NONNULL_END
