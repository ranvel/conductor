//
//  CDRSharedLog.h
//  Conductor
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue after a line is appended. userInfo[CDRSharedLogLineKey]
/// holds the timestamped line.
extern NSNotificationName const CDRSharedLogDidAppendNotification;
extern NSString * const CDRSharedLogLineKey;

/// The single activity-log sink: every line goes to os_log (subsystem
/// com.ranvel.Conductor, category "activity") and into a capped in-memory ring
/// buffer that UI surfaces render. Safe from any queue.
@interface CDRSharedLog : NSObject

+ (void)log:(NSString *)line;

/// The buffered (timestamped) lines, oldest first.
+ (NSArray<NSString *> *)bufferedLines;

@end

NS_ASSUME_NONNULL_END
