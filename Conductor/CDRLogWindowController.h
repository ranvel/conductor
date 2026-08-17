//
//  CDRLogWindowController.h
//  Conductor
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// The activity-log window (⌘L): renders CDRSharedLog's ring buffer and live
/// appends. Pure view — replays the buffer on init and observes
/// CDRSharedLogDidAppendNotification; zero engine coupling.
@interface CDRLogWindowController : NSWindowController

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
