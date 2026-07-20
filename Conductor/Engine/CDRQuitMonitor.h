//
//  CDRQuitMonitor.h
//  Conductor
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Running-app detection and polite termination (replace-flow.md §4).
/// Never force-terminates: -terminate sends the normal Quit Apple Event, so
/// the app may prompt to save and the user may cancel — both respected.
@interface CDRQuitMonitor : NSObject

+ (NSArray<NSRunningApplication *> *)runningInstancesOfBundleID:(NSString *)bundleID;

/// Requests termination of all running instances and waits (observing
/// NSWorkspace termination notifications) until they exit or the timeout
/// elapses. Completion is invoked on the main queue with YES iff no instance
/// remains running.
- (void)requestQuitOfBundleID:(NSString *)bundleID
                      timeout:(NSTimeInterval)timeout
                   completion:(void (^)(BOOL allQuit))completion;

@end

NS_ASSUME_NONNULL_END
