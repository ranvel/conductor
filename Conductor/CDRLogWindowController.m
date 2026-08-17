//
//  CDRLogWindowController.m
//  Conductor
//

#import "CDRLogWindowController.h"
#import "CDRSharedLog.h"

@interface CDRLogWindowController ()
@property (nonatomic) NSTextView *logView;
@property (nonatomic) id logObserver;
@end

@implementation CDRLogWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 640, 420)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Activity Log";
    [window center];

    self = [super initWithWindow:window];
    if (!self) return nil;

    self.windowFrameAutosaveName = @"CDRLogWindow";

    self.logView = [[NSTextView alloc] init];
    self.logView.editable = NO;
    self.logView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.logView.autoresizingMask = NSViewWidthSizable;
    NSScrollView *logScroll = [[NSScrollView alloc] init];
    logScroll.documentView = self.logView;
    logScroll.hasVerticalScroller = YES;
    logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *content = window.contentView;
    [content addSubview:logScroll];
    [NSLayoutConstraint activateConstraints:@[
        [logScroll.topAnchor constraintEqualToAnchor:content.topAnchor],
        [logScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [logScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [logScroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    for (NSString *line in [CDRSharedLog bufferedLines]) {
        [self appendLine:line];
    }
    __weak typeof(self) weakSelf = self;
    _logObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:CDRSharedLogDidAppendNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [weakSelf appendLine:note.userInfo[CDRSharedLogLineKey]];
    }];
    return self;
}

- (void)dealloc {
    if (_logObserver) [[NSNotificationCenter defaultCenter] removeObserver:_logObserver];
}

- (void)appendLine:(NSString *)line {
    if (!line) return;
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                             attributes:@{
        NSFontAttributeName: self.logView.font ?: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor labelColor],
    }];
    [self.logView.textStorage appendAttributedString:as];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
}

@end
