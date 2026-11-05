//
//  CDRWindowCopy.h
//  Conductor
//
//  The main window's wording and its row → button mapping, as pure functions
//  so tests can pin them without building a view.
//

#import <Foundation/Foundation.h>
#import "CDRAppRowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// "7 updates · 3 need you" for the title bar. Counts rows in the NEEDS YOU
/// and UPDATES sections; drops a clause that would be zero; "No updates"
/// when both are; empty when there are no managed apps at all.
NSString *CDRWindowSummary(NSArray<CDRAppRowModel *> *rows);

/// "Checked 4 min ago" / "Checked just now" / "Not checked yet".
NSString *CDRCheckedAgoString(NSDate * _Nullable lastCheck, NSDate *now);

/// YES when there is at least one app and every one of them is up to date —
/// the condition for the "Everything's up to date" pane.
BOOL CDRAllRowsUpToDate(NSArray<CDRAppRowModel *> *rows);

/// The row the window selects when the user hasn't chosen one: the first row
/// of the top-most section that isn't UP TO DATE. Nil when nothing needs
/// reading, so the right pane can say so instead.
CDRAppRowModel * _Nullable CDRDefaultSelection(NSArray<CDRAppRowModel *> *rows);

/// The detail header's primary button for a row: its title and the single
/// action it sends. Returns CDRAppRowActionNone (and no title) when the row's
/// pane carries its own buttons or nothing can be done.
CDRAppRowActions CDRPrimaryActionForRow(CDRAppRowModel *row, NSString * _Nullable * _Nullable outTitle);

NS_ASSUME_NONNULL_END
