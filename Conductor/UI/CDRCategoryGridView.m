//
//  CDRCategoryGridView.m
//  Conductor
//

#import "CDRCategoryGridView.h"
#import "CDRViews.h"

@interface CDRCategoryGridView ()
@property (nonatomic) NSMutableDictionary<NSNumber *, NSButton *> *checkboxes;
@end

@implementation CDRCategoryGridView

- (instancetype)initWithColumns:(NSInteger)columns showsRetracted:(BOOL)showsRetracted compact:(BOOL)compact {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _enabled = YES;
    _selectedTypes = CDRReleaseNoteTypeSetRetracted;
    _checkboxes = [NSMutableDictionary dictionary];

    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray array];
    NSMutableArray<NSView *> *current = [NSMutableArray array];
    for (NSInteger i = 0; i < CDRReleaseNoteTypeCount; i++) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)i;
        if (type == CDRReleaseNoteTypeRetracted && !showsRetracted) continue;

        NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
        checkbox.translatesAutoresizingMaskIntoConstraints = NO;
        checkbox.tag = type;
        [checkbox setAccessibilityLabel:CDRReleaseNoteTypeDisplayName(type)];
        self.checkboxes[@(type)] = checkbox;

        CDRBadgeView *badge = [[CDRBadgeView alloc] initWithType:type];
        badge.compact = compact;
        NSStackView *cell = [NSStackView stackViewWithViews:@[checkbox, badge]];
        cell.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        cell.spacing = 3;
        cell.alignment = NSLayoutAttributeCenterY;
        [current addObject:cell];
        if ((NSInteger)current.count == columns) {
            [rows addObject:current];
            current = [NSMutableArray array];
        }
    }
    if (current.count > 0) [rows addObject:current];

    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 10;
    grid.columnSpacing = compact ? 8 : 18;
    grid.xPlacement = NSGridCellPlacementLeading;
    grid.yPlacement = NSGridCellPlacementCenter;
    [self addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:self.topAnchor],
        [grid.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [grid.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
    ]];
    [self refresh];
    return self;
}

- (void)setSelectedTypes:(CDRReleaseNoteTypeSet)selectedTypes {
    _selectedTypes = selectedTypes | CDRReleaseNoteTypeSetRetracted;
    [self refresh];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self refresh];
}

- (NSButton *)checkboxForType:(CDRReleaseNoteType)type {
    return self.checkboxes[@(type)];
}

- (void)refresh {
    [self.checkboxes enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSButton *checkbox, BOOL *stop) {
        CDRReleaseNoteType type = (CDRReleaseNoteType)key.integerValue;
        BOOL locked = (type == CDRReleaseNoteTypeRetracted);
        checkbox.state = (locked || CDRReleaseNoteTypeSetContains(self.selectedTypes, type))
            ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.enabled = self.enabled && !locked;
    }];
}

- (void)checkboxToggled:(NSButton *)sender {
    CDRReleaseNoteType type = (CDRReleaseNoteType)sender.tag;
    if (type == CDRReleaseNoteTypeRetracted) {
        [self refresh];
        return;
    }
    CDRReleaseNoteTypeSet bit = CDRReleaseNoteTypeSetWithType(type);
    CDRReleaseNoteTypeSet types = self.selectedTypes;
    types = (sender.state == NSControlStateValueOn) ? (types | bit) : (types & ~bit);
    self.selectedTypes = types;
    if (self.onChange) self.onChange(self.selectedTypes);
}

@end
