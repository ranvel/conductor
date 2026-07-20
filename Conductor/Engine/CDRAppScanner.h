//
//  CDRAppScanner.h
//  Conductor
//

#import <Foundation/Foundation.h>

@class CDRAppRegistration;

NS_ASSUME_NONNULL_BEGIN

/// Discovers managed apps: a shallow scan of a directory (normally
/// /Applications) for .app bundles embedding a conductor.json. Scanning does
/// not verify anything — verification belongs to the update pipeline.
@interface CDRAppScanner : NSObject

/// Bundles whose conductor.json fails to parse are skipped and logged, never
/// fatal to the scan. Conductor itself is always excluded (it never manages
/// itself, replace-flow.md invariant).
- (NSArray<CDRAppRegistration *> *)scanDirectory:(NSURL *)directoryURL;

/// Convenience: scans /Applications.
- (NSArray<CDRAppRegistration *> *)scanApplicationsDirectory;

@end

NS_ASSUME_NONNULL_END
