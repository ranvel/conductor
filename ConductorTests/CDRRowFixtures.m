//
//  CDRRowFixtures.m
//  ConductorTests
//

#import "CDRRowFixtures.h"
#import "CDRAppRowModel_Private.h"
#import "CDRManifest.h"
#import "CDRInternetAccessPolicy.h"

@implementation CDRRowFixtures

static NSArray<NSDictionary *> *NoteDicts(NSArray<NSArray<NSString *> *> *pairs) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray<NSString *> *pair in pairs) [items addObject:@{@"type": pair[0], @"text": pair[1]}];
    return items;
}

+ (CDRAppRowModel *)rowNamed:(NSString *)name
                       state:(CDRAppRowState)state
                   installed:(NSString *)installed
                  advertised:(NSString *)advertised
                       notes:(NSArray<NSArray<NSString *> *> *)notes
                     history:(NSDictionary<NSString *, NSArray<NSArray<NSString *> *> *> *)history {
    CDRAppRowModel *row = [[CDRAppRowModel alloc] init];
    row.appName = name;
    row.bundleID = [@"com.example." stringByAppendingString:
                    [[name lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"-"]];
    // A real bundle path gives the render a real icon; it is never opened.
    row.appURL = [NSURL fileURLWithPath:@"/System/Applications/Utilities/Terminal.app"];
    row.installedVersion = installed;
    row.installedVersionDisplay = installed;
    row.state = state;
    row.stateLine = name;
    row.developerName = @"Cedar Syntax LLC";
    row.vendorURL = [NSURL URLWithString:@"https://example.com"];

    if (advertised) {
        // Through the real parser, so fixtures can't hold notes a manifest couldn't.
        NSMutableDictionary *dict = [@{
            @"conductor_manifest": @1,
            @"bundle_id": row.bundleID,
            @"version": advertised,
            @"url": @"https://example.com/app.dmg",
            @"released": @"2026-11-03",
            @"size": @19293798,
            @"changelog_url": @"https://example.com/changelog",
            @"notes": NoteDicts(notes ?: @[]),
        } mutableCopy];
        NSMutableArray *entries = [NSMutableArray array];
        [history enumerateKeysAndObjectsUsingBlock:^(NSString *version, NSArray *pairs, BOOL *stop) {
            [entries addObject:@{@"version": version, @"date": @"2026-10-14", @"notes": NoteDicts(pairs)}];
        }];
        dict[@"history"] = entries;
        CDRManifest *manifest = [CDRManifest manifestWithData:
            [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL] error:NULL];
        row.advertisedVersion = advertised;
        row.releases = [manifest releasesNewerThanVersion:installed];
        row.noteTypes = manifest.advertisedRelease.typeSet;
        row.releaseDate = manifest.advertisedRelease.date;
        row.artifactSize = manifest.artifactSize;
        row.changelogURL = manifest.changelogURL;
    }

    switch (state) {
        case CDRAppRowStateAvailable:
            row.availableVersion = advertised;
            row.actions = CDRAppRowActionInstall | CDRAppRowActionCheckNow | CDRAppRowActionIgnore;
            row.contributesToBadge = YES;
            break;
        case CDRAppRowStateHeld:
        case CDRAppRowStateNeedsNetworkApproval:
            row.actions = CDRAppRowActionInstall | CDRAppRowActionCheckNow | CDRAppRowActionIgnore;
            break;
        case CDRAppRowStateStoppedAtMajor:
            row.actions = CDRAppRowActionInstall | CDRAppRowActionAlwaysAllowMajor
                | CDRAppRowActionCheckNow | CDRAppRowActionIgnore;
            break;
        case CDRAppRowStateDeferred:
            row.actions = CDRAppRowActionCheckNow | CDRAppRowActionInstallDeferred | CDRAppRowActionIgnore;
            row.deferralDurationName = @"3 days";
            break;
        case CDRAppRowStateRetracted:
            row.noteTypes = CDRReleaseNoteTypeSetRetracted;
            row.actions = CDRAppRowActionCheckNow | CDRAppRowActionAcknowledge | CDRAppRowActionIgnore
                | CDRAppRowActionVendorSite;
            row.contributesToBadge = YES;
            break;
        case CDRAppRowStateRecalled:
            row.noteTypes = CDRReleaseNoteTypeSetRetracted;
            row.actions = CDRAppRowActionCheckNow | CDRAppRowActionIgnore | CDRAppRowActionVendorSite;
            break;
        case CDRAppRowStateWaitingForQuit:
            row.actions = CDRAppRowActionCancelPending;
            break;
        case CDRAppRowStateWorking:
        case CDRAppRowStateInspecting:
            row.actions = CDRAppRowActionNone;
            break;
        case CDRAppRowStateIgnored:
            row.actions = CDRAppRowActionCheckNow | CDRAppRowActionUnignore;
            break;
        case CDRAppRowStateCheckFailed:
            row.errorDescription = @"The update server could not be reached.";
            row.actions = CDRAppRowActionCheckNow | CDRAppRowActionIgnore | CDRAppRowActionVendorSite;
            break;
        default:
            row.actions = CDRAppRowActionCheckNow | CDRAppRowActionIgnore;
            break;
    }
    return row;
}

+ (NSArray<CDRAppRowModel *> *)designRows {
    CDRAppRowModel *vancast = [self rowNamed:@"Van-cast" state:CDRAppRowStateNeedsNetworkApproval
                                   installed:@"0.4" advertised:@"0.5"
                                       notes:@[@[@"added", @"Subscribe to any podcast feed."],
                                               @[@"improved", @"Faster library scans."],
                                               @[@"fixed", @"Artwork no longer flickers."]]
                                     history:nil];

    // What the network gate found for Van-cast: 0.5 gains access and says why.
    vancast.networkTitle = @"Gains internet access";
    vancast.networkTone = CDRNetworkRowToneAttention;
    vancast.networkDetail = @"0.4 made no connections · 0.5 says where it connects, and why";
    vancast.networkTrailing = @"Team ID matches";
    vancast.networkPolicyRows = [CDRInternetAccessPolicy policyWithPropertyList:@{@"Connections": @[
        @{@"Host": @"*", @"Purpose": @"Checks your subscriptions for new episodes and downloads them."},
        @{@"Host": @"search.example.com", @"Purpose": @"Podcast directory search, only when you type in Search."},
    ]} strings:nil].rows;

    CDRAppRowModel *smoothMove = [self rowNamed:@"SmoothMove" state:CDRAppRowStateHeld
                                      installed:@"1.3" advertised:@"1.4"
                                          notes:@[@[@"removed", @"Snap-resistance override for external displays. macOS now handles this itself."],
                                                  @[@"fixed", @"Windows keep their size across Spaces."]]
                                        history:nil];
    smoothMove.heldTypes = CDRReleaseNoteTypeSetRemoved;

    CDRAppRowModel *fastmail = [self rowNamed:@"Fastmail SSB" state:CDRAppRowStateRetracted
                                    installed:@"1.1" advertised:nil notes:nil history:nil];
    fastmail.retractedVersion = @"1.2";

    CDRAppRowModel *muwav = [self rowNamed:@"muwav" state:CDRAppRowStateAvailable
                                 installed:@"1.2" advertised:@"1.4"
                                     notes:@[
        @[@"notice", @"Your library moves to a new format on first launch. Macs still running 1.2 can’t open it afterwards."],
        @[@"removed", @"Import from iTunes Library XML. Use File › Import from Music instead."],
        @[@"security", @"A crafted playlist file could read outside the library folder."],
        @[@"security", @"Artwork downloads now verify the server certificate."],
        @[@"added", @"Pin any wave to the sidebar."],
        @[@"added", @"Set crossfade length per wave."],
        @[@"improved", @"Wave generation on large libraries is faster and no longer blocks scrolling."],
        @[@"fixed", @"Scrubbing no longer skips the last second of a track."],
        @[@"fixed", @"AirPlay output resumes after the Mac wakes."],
    ]
                                   history:@{@"1.3": @[@[@"disabled", @"Lyrics view is off while it is rebuilt."],
                                                       @[@"added", @"Smart waves from a single track."],
                                                       @[@"improved", @"Lower memory use during playback."],
                                                       @[@"fixed", @"The mini player remembers its position."]]}];

    // The Main window design's NETWORK row.
    muwav.networkTitle = @"No network access";
    muwav.networkTone = CDRNetworkRowTonePositive;
    muwav.networkDetail = @"Same as 1.2 · this build makes no connections";
    muwav.networkTrailing = @"Team ID matches";

    CDRAppRowModel *understudy = [self rowNamed:@"Understudy" state:CDRAppRowStateInspecting
                                      installed:@"0.8" advertised:@"0.9"
                                          notes:@[@[@"added", @"Rehearse with a second voice."],
                                                  @[@"fixed", @"Scripts with tabs import cleanly."]]
                                        history:nil];
    understudy.operationPhase = CDRUpdatePhaseDownloading;
    understudy.networkTitle = @"No network access";
    understudy.networkTone = CDRNetworkRowTonePositive;
    understudy.networkDetail = @"This app makes no connections";

    CDRAppRowModel *xkcd = [self rowNamed:@"xkcd Adopted" state:CDRAppRowStateDeferred
                                installed:@"2.0.1" advertised:@"2.0.2"
                                    notes:@[@[@"fixed", @"Alt text wraps on narrow windows."]]
                                  history:nil];
    xkcd.deferredUntil = [NSDate dateWithTimeIntervalSinceNow:1.6 * 86400];

    CDRAppRowModel *unxip = [self rowNamed:@"Swift Unxip" state:CDRAppRowStateStoppedAtMajor
                                 installed:@"0.9" advertised:@"1.0"
                                     notes:@[@[@"notice", @"Requires macOS 15 or later."],
                                             @[@"added", @"Resume an interrupted extraction."],
                                             @[@"improved", @"Uses every performance core."]]
                                   history:nil];

    CDRAppRowModel *fakear = [self rowNamed:@"Fakear" state:CDRAppRowStateUpToDate
                                  installed:@"1.0.3" advertised:nil notes:nil history:nil];

    return @[vancast, smoothMove, fastmail, muwav, understudy, xkcd, unxip, fakear];
}

+ (CDRAppRowModel *)designRowNamed:(NSString *)name {
    for (CDRAppRowModel *row in [self designRows]) {
        if ([row.appName isEqualToString:name]) return row;
    }
    return nil;
}

@end
