//
//  CDRNotarizationCheck.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Confirms Apple's notarization ticket exists for exactly this bundle by
/// shelling out to `spctl --assess --type execute`. The supported SecAssessment
/// APIs are awkward from third-party code; spctl is the honest tool
/// (replace-flow.md §3.4). If Apple ever ships a real API, only this class
/// changes.
@interface CDRNotarizationCheck : NSObject

+ (BOOL)assessBundleAtURL:(NSURL *)url error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
