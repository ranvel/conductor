//
//  CDRSharedLog.m
//  Conductor
//

#import "CDRSharedLog.h"
#import <os/log.h>

NSNotificationName const CDRSharedLogDidAppendNotification = @"CDRSharedLogDidAppendNotification";
NSString * const CDRSharedLogLineKey = @"line";

static const NSUInteger kCDRSharedLogCapacity = 2000;

@implementation CDRSharedLog

+ (os_log_t)osLog {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.ranvel.Conductor", "activity");
    });
    return log;
}

+ (NSMutableArray<NSString *> *)buffer {
    static NSMutableArray<NSString *> *buffer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        buffer = [NSMutableArray array];
    });
    return buffer;
}

+ (void)log:(NSString *)line {
    os_log([self osLog], "%{public}@", line);

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *stamped = [NSString stringWithFormat:@"[%@] %@",
                         [fmt stringFromDate:[NSDate date]], line];

    NSMutableArray<NSString *> *buffer = [self buffer];
    @synchronized (buffer) {
        [buffer addObject:stamped];
        if (buffer.count > kCDRSharedLogCapacity) {
            [buffer removeObjectsInRange:NSMakeRange(0, buffer.count - kCDRSharedLogCapacity)];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CDRSharedLogDidAppendNotification
                                                            object:nil
                                                          userInfo:@{CDRSharedLogLineKey: stamped}];
    });
}

+ (NSArray<NSString *> *)bufferedLines {
    NSMutableArray<NSString *> *buffer = [self buffer];
    @synchronized (buffer) {
        return [buffer copy];
    }
}

@end
