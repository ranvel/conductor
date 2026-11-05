//
//  CDRSettingsWindowController+Testing.h
//  ConductorTests
//
//  Test-only view of the Settings form's controls.
//

#import "CDRSettingsWindowController.h"
#import "CDRCategoryGridView.h"

@interface CDRSettingsWindowController (Testing)
@property (nonatomic, readonly) NSScrollView *scrollView;
@property (nonatomic, readonly) NSSegmentedControl *deferralControl;
@property (nonatomic, readonly) NSSwitch *stopAtMajorSwitch;
@property (nonatomic, readonly) NSArray *schemeCards;   // CDRSchemeCardView: -selected, -button
@property (nonatomic, readonly) CDRCategoryGridView *shownGrid;
@property (nonatomic, readonly) CDRCategoryGridView *holdGrid;
@property (nonatomic, readonly) NSSwitch *requireApprovalSwitch;
@property (nonatomic, readonly) NSSwitch *policyExemptsSwitch;
@property (nonatomic, readonly) NSPopUpButton *cadencePopup;
- (void)refreshFromDefaults;
@end
