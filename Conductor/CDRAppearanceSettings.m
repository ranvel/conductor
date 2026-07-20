//
//  CDRAppearanceSettings.m
//  Conductor
//

#import "CDRAppearanceSettings.h"

NSString * const CDRShowMenuBarItemDefaultsKey = @"CDRShowMenuBarItem";
NSString * const CDRShowDockIconDefaultsKey = @"CDRShowDockIcon";

static BOOL ReadWithDefaultYES(NSUserDefaults *defaults, NSString *key) {
    id value = [defaults objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

BOOL CDRShowMenuBarItemSetting(NSUserDefaults *defaults) {
    BOOL menuBar = ReadWithDefaultYES(defaults, CDRShowMenuBarItemDefaultsKey);
    BOOL dock = ReadWithDefaultYES(defaults, CDRShowDockIconDefaultsKey);
    if (!menuBar && !dock) return YES; // never invisible; menu bar wins
    return menuBar;
}

BOOL CDRShowDockIconSetting(NSUserDefaults *defaults) {
    return ReadWithDefaultYES(defaults, CDRShowDockIconDefaultsKey);
}
