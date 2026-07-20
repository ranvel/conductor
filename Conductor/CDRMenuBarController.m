//
//  CDRMenuBarController.m
//  Conductor
//

#import "CDRMenuBarController.h"
#import "CDRDevModeSession.h"

@interface CDRMenuBarController () <NSMenuDelegate>
@property (nonatomic) CDRDevModeSession *session;
@property (nonatomic, nullable) NSStatusItem *statusItem;
@end

@implementation CDRMenuBarController

- (instancetype)initWithSession:(CDRDevModeSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = session;
    _rowModels = @[];
    _preferredVisible = YES;
    return self;
}

- (void)dealloc {
    if (_statusItem) [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
}

#pragma mark - Visibility & icon

- (BOOL)effectiveVisible {
    // The unmissable dev-mode state overrides the user's preference,
    // session-only by construction.
    return self.preferredVisible || self.session.devModeEnabled;
}

- (void)setPreferredVisible:(BOOL)preferredVisible {
    _preferredVisible = preferredVisible;
    [self updateStatusItem];
}

- (void)setRowModels:(NSArray<CDRAppRowModel *> *)rowModels {
    _rowModels = [rowModels copy];
    [self updateStatusItem];
}

- (void)updateStatusItem {
    if (![self effectiveVisible]) {
        if (self.statusItem) {
            [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
            self.statusItem = nil;
        }
        return;
    }

    if (!self.statusItem) {
        self.statusItem = [[NSStatusBar systemStatusBar]
            statusItemWithLength:NSSquareStatusItemLength];
        // A fixed autosave name keeps macOS's per-item visibility memory
        // stable across launches; visible=YES clears any stale hidden state.
        self.statusItem.autosaveName = @"CDRStatusItem";
        self.statusItem.visible = YES;
        NSMenu *menu = [[NSMenu alloc] init];
        menu.delegate = self;
        self.statusItem.menu = menu;
    }

    BOOL badged = NO;
    for (CDRAppRowModel *row in self.rowModels) {
        if (row.contributesToBadge) { badged = YES; break; }
    }

    NSImage *image;
    if (self.session.devModeEnabled) {
        image = [NSImage imageWithSystemSymbolName:@"wrench.and.screwdriver.fill"
                          accessibilityDescription:@"Conductor (dev mode)"];
        image = [image imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPaletteColors:@[[NSColor systemOrangeColor]]]];
        image.template = NO;
    } else {
        NSString *symbol = badged ? @"arrow.triangle.2.circlepath.circle.fill"
                                  : @"arrow.triangle.2.circlepath";
        NSString *description = badged ? @"Conductor — updates available" : @"Conductor";
        image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
        image.template = YES;
    }
    self.statusItem.button.image = image;
}

#pragma mark - Menu building

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];

    if (self.session.devModeEnabled) {
        NSString *text = [NSString stringWithFormat:@"DEV MODE — %@ — insecure connections permitted",
                          self.session.devModeBundleID];
        NSMenuItem *banner = [[NSMenuItem alloc] initWithTitle:text action:nil keyEquivalent:@""];
        banner.attributedTitle = [[NSAttributedString alloc] initWithString:text attributes:@{
            NSForegroundColorAttributeName: [NSColor systemOrangeColor],
            NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]],
        }];
        [menu addItem:banner];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    if (self.rowModels.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No managed apps found"
                                                       action:nil keyEquivalent:@""];
        [menu addItem:empty];
    }

    for (CDRAppRowModel *row in self.rowModels) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@", row.appName, row.stateLine];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        if (row.state == CDRAppRowStateIgnored) {
            item.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            }];
        }
        item.submenu = [self submenuForRow:row];
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *checkAll = [[NSMenuItem alloc] initWithTitle:@"Check for Updates"
                                                      action:@selector(checkAllChosen:)
                                               keyEquivalent:@""];
    checkAll.target = self;
    [menu addItem:checkAll];

    NSMenuItem *openWindow = [[NSMenuItem alloc] initWithTitle:@"Open Conductor"
                                                        action:@selector(openWindowChosen:)
                                                 keyEquivalent:@""];
    openWindow.target = self;
    [menu addItem:openWindow];

    if (self.onOpenSettings) {
        NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                          action:@selector(openSettingsChosen:)
                                                   keyEquivalent:@","];
        settings.target = self;
        [menu addItem:settings];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Conductor"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
}

- (NSMenu *)submenuForRow:(CDRAppRowModel *)row {
    NSMenu *submenu = [[NSMenu alloc] init];

    struct { CDRAppRowActions action; NSString *title; } entries[] = {
        { CDRAppRowActionInstall,       row.availableVersion
            ? [NSString stringWithFormat:@"Install %@", row.availableVersion] : @"Install" },
        { CDRAppRowActionCheckNow,      @"Check Now" },
        { CDRAppRowActionCancelPending, @"Cancel Pending Update" },
        { CDRAppRowActionVendorSite,    @"Developer's Site" },
        { CDRAppRowActionIgnore,        @"Ignore" },
        { CDRAppRowActionUnignore,      @"Stop Ignoring" },
    };
    for (size_t i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        if (!(row.actions & entries[i].action)) continue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entries[i].title
                                                      action:@selector(rowActionChosen:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{@"bundleID": row.bundleID, @"action": @(entries[i].action)};
        [submenu addItem:item];
    }

    if (submenu.numberOfItems == 0) {
        NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:row.stateLine action:nil keyEquivalent:@""];
        [submenu addItem:none];
    }
    return submenu;
}

#pragma mark - Actions

- (void)rowActionChosen:(NSMenuItem *)item {
    NSDictionary *info = item.representedObject;
    NSString *bundleID = info[@"bundleID"];
    CDRAppRowActions action = [info[@"action"] unsignedIntegerValue];
    if (bundleID && self.onRowAction) self.onRowAction(bundleID, action);
}

- (void)checkAllChosen:(id)sender {
    if (self.onCheckAll) self.onCheckAll();
}

- (void)openWindowChosen:(id)sender {
    if (self.onOpenWindow) self.onOpenWindow();
}

- (void)openSettingsChosen:(id)sender {
    if (self.onOpenSettings) self.onOpenSettings();
}

@end
