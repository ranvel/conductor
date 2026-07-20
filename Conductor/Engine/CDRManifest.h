//
//  CDRManifest.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Closed urgency vocabulary (deferral.md). The manifest carries only a token;
/// Conductor renders its own fixed copy. Unknown tokens map to None.
typedef NS_ENUM(NSInteger, CDRUrgency) {
    CDRUrgencyNone = 0,
    CDRUrgencySystemRisk,
    CDRUrgencyDataLoss,
    CDRUrgencyDataExfiltration,
};

/// The vendor-served update manifest. Unauthenticated by design — nothing in
/// it is a security input except the artifact URL, whose payload is verified
/// independently (Team ID pinning, replace-flow.md §3).
@interface CDRManifest : NSObject

@property (nonatomic, readonly) NSInteger formatVersion;      // conductor_manifest
@property (nonatomic, readonly) NSString *bundleID;
@property (nonatomic, readonly) NSString *version;            // advisory / display
@property (nonatomic, readonly, nullable) NSString *build;
@property (nonatomic, readonly) NSURL *artifactURL;
@property (nonatomic, readonly, nullable) NSString *sha256;   // integrity hint, not a security boundary
@property (nonatomic, readonly) CDRUrgency urgency;
@property (nonatomic, readonly, nullable) NSURL *changelogURL;
@property (nonatomic, readonly, nullable) NSString *minSystemVersion;

+ (nullable instancetype)manifestWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
