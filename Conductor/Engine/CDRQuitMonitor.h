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

/// Observe-only ("update on quit"): never sends terminate, no timeout.
/// Completion fires on the main queue once no instance of the bundle ID
/// remains running — immediately if none are running now. One observation per
/// monitor instance. Main queue only.
- (void)observeTerminationOfBundleID:(NSString *)bundleID
                          completion:(void (^)(void))completion;

/// Cancels a pending observation; its completion will never fire. Main queue
/// only. No-op when nothing is being observed.
- (void)cancelObservation;

@end

NS_ASSUME_NONNULL_END
