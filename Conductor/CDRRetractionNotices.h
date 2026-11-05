//
//  CDRRetractionNotices.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A retraction (State A) the user has not acknowledged yet: a version they
/// were told about was withdrawn before they installed it.
///
/// The policy's memory is deliberately one-time — the decision that detects
/// a retraction also clears it, so the *notification* fires once
/// (retraction.md). This is the presentation side of the same event: the
/// row and pane keep their amber banner until the user says "Got it", even
/// across later checks and relaunches. Nothing here is a policy input.
@interface CDRRetractionNotice : NSObject
@property (nonatomic, readonly, copy) NSString *version;
/// When Conductor surfaced that version to the user, if known.
@property (nonatomic, readonly, nullable) NSDate *advertisedAt;
/// When Conductor saw it withdrawn.
@property (nonatomic, readonly) NSDate *pulledAt;
+ (instancetype)noticeWithVersion:(NSString *)version
                     advertisedAt:(nullable NSDate *)advertisedAt
                         pulledAt:(NSDate *)pulledAt;
@end

extern NSString * const CDRRetractionNoticesDefaultsKey;   // { bundleID: {version, advertised_at, pulled_at} }

/// Nil when there is none (or the stored entry is malformed).
CDRRetractionNotice * _Nullable CDRRetractionNoticeForBundleID(NSString *bundleID, NSUserDefaults *defaults);
/// Nil removes the app's notice.
void CDRSetRetractionNotice(CDRRetractionNotice * _Nullable notice, NSString *bundleID, NSUserDefaults *defaults);

NS_ASSUME_NONNULL_END
