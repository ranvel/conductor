//
//  CDRVersion.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Numeric-aware, component-wise version comparison.
///
/// Security note (replace-flow.md §3.2): the downgrade-refusal check compares
/// versions read from the staged bundle's Info.plist against the installed
/// copy's — never versions claimed by the unauthenticated manifest.
@interface CDRVersion : NSObject

/// Compares two dotted version strings component-wise, numerically where both
/// components are numeric ("1.9" < "1.10"), lexically otherwise. Missing
/// components compare as 0 ("1.2" == "1.2.0").
+ (NSComparisonResult)compare:(NSString *)a to:(NSString *)b;

/// Whether the candidate (short version + optional build) is strictly newer
/// than the baseline. Short versions are compared first; an equal short
/// version falls through to the build numbers when both are present.
+ (BOOL)isVersion:(NSString *)candidateShort
            build:(nullable NSString *)candidateBuild
      newerThan:(NSString *)baselineShort
            build:(nullable NSString *)baselineBuild;

@end

NS_ASSUME_NONNULL_END
