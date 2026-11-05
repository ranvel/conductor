//
//  testee-main.m
//  ConductorTestee — the dummy managed app for Conductor's e2e harness.
//
//  A real, signable AppKit app that does nothing but display its own version
//  and quit politely, so the quit-check and swap steps can be exercised.
//

#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        NSBundle *bundle = [NSBundle mainBundle];
        NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
        NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";

        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 360, 120)
                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                        backing:NSBackingStoreBuffered
                          defer:NO];
        window.title = @"ConductorTestee";
        [window center];

        NSTextField *label = [NSTextField labelWithString:
            [NSString stringWithFormat:@"ConductorTestee %@ (%@)", version, build]];
        label.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:window.contentView.centerYAnchor],
        ]];

        [window makeKeyAndOrderFront:nil];
        [app run];
    }
    return 0;
}
