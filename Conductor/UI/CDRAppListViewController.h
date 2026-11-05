//
//  CDRAppListViewController.h
//  Conductor
//

#import <AppKit/AppKit.h>
#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The main window's left pane: a search field and the managed apps grouped
/// into NEEDS YOU / UPDATES / UP TO DATE (/ NOT CHECKED). Renders only from
/// row models; every click leaves through a block.
@interface CDRAppListViewController : NSViewController

@property (nonatomic, copy) NSArray<CDRAppRowModel *> *rowModels;
/// Nil when nothing is selected. Setting it scrolls the row into view.
@property (nonatomic, copy, nullable) NSString *selectedBundleID;

@property (nonatomic, copy, nullable) void (^onSelectionChanged)(NSString * _Nullable bundleID);
@property (nonatomic, copy, nullable) void (^onRowAction)(NSString *bundleID, CDRAppRowActions action);

/// The aggregate progress line under the list (hidden when inactive).
- (void)setProgressActive:(BOOL)active fraction:(double)fraction detail:(nullable NSString *)detail;

/// Pure: the rows that survive `query` (case- and diacritic-insensitive match
/// on the app name), grouped by section in display order. Each element is
/// either an NSNumber (a CDRAppRowSection header) or a CDRAppRowModel.
+ (NSArray *)listItemsForRowModels:(NSArray<CDRAppRowModel *> *)rowModels query:(nullable NSString *)query;

@end

NS_ASSUME_NONNULL_END
