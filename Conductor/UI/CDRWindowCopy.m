//
//  CDRWindowCopy.m
//  Conductor
//

#import "CDRWindowCopy.h"

NSString *CDRWindowSummary(NSArray<CDRAppRowModel *> *rows) {
    if (rows.count == 0) return @"";
    NSUInteger needsYou = 0, updates = 0;
    for (CDRAppRowModel *row in rows) {
        if (row.section == CDRAppRowSectionNeedsYou) needsYou++;
        else if (row.section == CDRAppRowSectionUpdates) updates++;
    }
    NSUInteger total = needsYou + updates;
    if (total == 0) return @"No updates";
    NSString *summary = [NSString stringWithFormat:@"%lu %@", (unsigned long)total,
                         total == 1 ? @"update" : @"updates"];
    if (needsYou > 0) {
        summary = [summary stringByAppendingFormat:@" · %lu %@ you", (unsigned long)needsYou,
                   needsYou == 1 ? @"needs" : @"need"];
    }
    return summary;
}

NSString *CDRCheckedAgoString(NSDate *lastCheck, NSDate *now) {
    if (!lastCheck) return @"Not checked yet";
    NSTimeInterval elapsed = [now timeIntervalSinceDate:lastCheck];
    if (elapsed < 60) return @"Checked just now";
    if (elapsed < 3600) return [NSString stringWithFormat:@"Checked %ld min ago", (long)(elapsed / 60)];
    if (elapsed < 86400) return [NSString stringWithFormat:@"Checked %ld hr ago", (long)(elapsed / 3600)];
    NSInteger days = (NSInteger)(elapsed / 86400);
    return days == 1 ? @"Checked yesterday" : [NSString stringWithFormat:@"Checked %ld days ago", (long)days];
}

BOOL CDRAllRowsUpToDate(NSArray<CDRAppRowModel *> *rows) {
    if (rows.count == 0) return NO;
    for (CDRAppRowModel *row in rows) {
        if (row.state != CDRAppRowStateUpToDate) return NO;
    }
    return YES;
}

CDRAppRowModel *CDRDefaultSelection(NSArray<CDRAppRowModel *> *rows) {
    for (NSInteger section = 0; section < CDRAppRowSectionCount; section++) {
        if (section == CDRAppRowSectionUpToDate) continue;
        for (CDRAppRowModel *row in rows) {
            if (row.section == section) return row;
        }
    }
    return nil;
}

CDRAppRowActions CDRPrimaryActionForRow(CDRAppRowModel *row, NSString **outTitle) {
    NSString *title = nil;
    CDRAppRowActions action = CDRAppRowActionNone;
    switch (row.state) {
        case CDRAppRowStateAvailable:
            title = [NSString stringWithFormat:@"Update to %@", row.advertisedVersion ?: @"latest"];
            action = CDRAppRowActionInstall;
            break;
        case CDRAppRowStateHeld:
            title = [NSString stringWithFormat:@"Install %@", row.advertisedVersion ?: @"update"];
            action = CDRAppRowActionInstall;
            break;
        case CDRAppRowStateNeedsNetworkApproval:
            title = @"Approve…";
            action = CDRAppRowActionInstall;
            break;
        case CDRAppRowStateUpToDate:
        case CDRAppRowStateUnknown:
        case CDRAppRowStateCheckFailed:
            title = @"Check now";
            action = CDRAppRowActionCheckNow;
            break;
        case CDRAppRowStateIgnored:
            title = @"Stop ignoring";
            action = CDRAppRowActionUnignore;
            break;
        case CDRAppRowStateWaitingForQuit:
            title = @"Cancel update";
            action = CDRAppRowActionCancelPending;
            break;
        // These panes carry their own buttons (or have nothing to press).
        case CDRAppRowStateDeferred:
        case CDRAppRowStateStoppedAtMajor:
        case CDRAppRowStateRetracted:
        case CDRAppRowStateRecalled:
        case CDRAppRowStateInspecting:
        case CDRAppRowStateWorking:
            break;
    }
    // Never offer a button the row model says can't be pressed.
    if (action != CDRAppRowActionNone && !(row.actions & action)) {
        title = nil;
        action = CDRAppRowActionNone;
    }
    if (outTitle) *outTitle = title;
    return action;
}
