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

/// Invoked with the selected registration when the user clicks Check / Install.
@property (nonatomic, copy, nullable) void (^onCheck)(CDRAppRegistration *registration);
@property (nonatomic, copy, nullable) void (^onInstall)(CDRAppRegistration *registration);

/// Appends a timestamped line to the status log (safe from any queue).
- (void)appendLog:(NSString *)line;

/// Enables the Install button for the given bundle ID (an update is known to
/// be available), with the version used for display.
- (void)setInstallAvailable:(BOOL)available forBundleID:(NSString *)bundleID version:(nullable NSString *)version;

@end

NS_ASSUME_NONNULL_END
