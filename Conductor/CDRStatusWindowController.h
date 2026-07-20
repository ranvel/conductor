//
//  CDRStatusWindowController.h
//  Conductor
//

#import <Cocoa/Cocoa.h>

@class CDRAppRegistration;
@class CDRDevModeSession;

NS_ASSUME_NONNULL_BEGIN

/// Minimal milestone UI: the visible registrations, a Check/Install action
/// per selection, and a scrolling status log. Not the product UI.
@interface CDRStatusWindowController : NSWindowController

- (instancetype)initWithSession:(CDRDevModeSession *)session;

/// Registrations to display (already filtered through the session by the caller).
@property (nonatomic, copy) NSArray<CDRAppRegistration *> *registrations;

/// Invoked with the selected registration when the user clicks Check Now /
/// Install. Check Now is the deliberate per-app act that breaks through a
/// soak (deferral.md); the caller decides what that means.
@property (nonatomic, copy, nullable) void (^onCheck)(CDRAppRegistration *registration);
@property (nonatomic, copy, nullable) void (^onInstall)(CDRAppRegistration *registration);
/// Invoked when the user clicks Check All — the global scan, which must NOT
/// break through soaks.
@property (nonatomic, copy, nullable) void (^onCheckAll)(void);

/// Appends a timestamped line to the status log (safe from any queue).
- (void)appendLog:(NSString *)line;

/// Sets the Available-column text for the app's row (nil → "—") and whether
/// Install is enabled for it. Deferred / available / retracted are different
/// row texts (roadmap.md M2) — real list rows arrive with the M3 UI.
- (void)setRowStatus:(nullable NSString *)status
      installEnabled:(BOOL)enabled
         forBundleID:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
