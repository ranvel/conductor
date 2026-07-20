//
//  CDRQuarantine.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Recursive removal of com.apple.quarantine (replace-flow.md §6). Runs ONLY
/// after the full verification pass — Conductor has already applied a stricter
/// check than Gatekeeper (Gatekeeper does not pin Team IDs across versions),
/// so first-launch prompts and App Translocation are pure downside at that
/// point. com.apple.provenance is left alone (cannot be removed; harmless).
@interface CDRQuarantine : NSObject

+ (BOOL)stripQuarantineRecursivelyAtURL:(NSURL *)rootURL error:(NSError **)error;

/// Whether any item in the tree still carries com.apple.quarantine (test aid).
+ (BOOL)treeContainsQuarantineAtURL:(NSURL *)rootURL;

@end

NS_ASSUME_NONNULL_END
