//
//  CDRNetworkGateTests.m
//  ConductorTests
//
//  The pure parts of the network gate: posture from entitlements, the
//  change between two postures, the ask / don't-ask rule, the Internet
//  Access Policy parser, and the entitlement reader against real bundles.
//

#import <XCTest/XCTest.h>
#import "CDRBundleInspector.h"
#import "CDRInternetAccessPolicy.h"
#import "CDRNetworkInspection.h"
#import "CDRUpdatePreferences.h"

@interface CDRNetworkGateTests : XCTestCase
@end

@implementation CDRNetworkGateTests

static NSDictionary *Entitlements(BOOL sandbox, BOOL client, BOOL server) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (sandbox) dict[CDREntitlementAppSandbox] = @YES;
    if (client) dict[CDREntitlementNetworkClient] = @YES;
    if (server) dict[CDREntitlementNetworkServer] = @YES;
    return dict;
}

static CDRUpdatePreferences *GatePrefs(BOOL require, BOOL policyExempts) {
    CDRMutableUpdatePreferences *prefs = [[CDRUpdatePreferences defaultPreferences] mutableCopy];
    prefs.requireNetworkApproval = require;
    prefs.policyExemptsApproval = policyExempts;
    return [prefs copy];
}

#pragma mark - Posture

- (void)testPostureFromEntitlements {
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(Entitlements(YES, NO, NO)), CDRNetworkPostureNone);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(Entitlements(YES, YES, NO)), CDRNetworkPostureClient);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(Entitlements(YES, NO, YES)), CDRNetworkPostureServer);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(Entitlements(YES, YES, YES)), CDRNetworkPostureBoth);
    // Not sandboxed: unrestricted, whatever network keys it carries (they
    // only mean something inside the sandbox) — including none at all.
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(@{}), CDRNetworkPostureUnrestricted);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(Entitlements(NO, NO, NO)), CDRNetworkPostureUnrestricted);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(Entitlements(NO, YES, YES)), CDRNetworkPostureUnrestricted);
}

- (void)testOnlyARealBooleanTrueCountsAsAnEntitlement {
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(@{CDREntitlementAppSandbox: @NO}), CDRNetworkPostureUnrestricted);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements(@{CDREntitlementAppSandbox: @"true"}),
                   CDRNetworkPostureUnrestricted);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements((@{CDREntitlementAppSandbox: @YES,
                                                        CDREntitlementNetworkClient: @NO})),
                   CDRNetworkPostureNone);
    XCTAssertEqual(CDRNetworkPostureFromEntitlements((@{CDREntitlementAppSandbox: @YES,
                                                        CDREntitlementNetworkClient: @"yes"})),
                   CDRNetworkPostureNone);
}

- (void)testHasAccess {
    XCTAssertFalse(CDRNetworkPostureHasAccess(CDRNetworkPostureNone));
    XCTAssertFalse(CDRNetworkPostureHasAccess(CDRNetworkPostureUnknown), @"unknown is never 'has access'…");
    for (NSNumber *posture in @[@(CDRNetworkPostureClient), @(CDRNetworkPostureServer),
                                @(CDRNetworkPostureBoth), @(CDRNetworkPostureUnrestricted)]) {
        XCTAssertTrue(CDRNetworkPostureHasAccess((CDRNetworkPosture)posture.integerValue));
    }
}

#pragma mark - Change

- (void)testChangeTable {
    // installed, staged, expected
    NSArray<NSArray<NSNumber *> *> *table = @[
        @[@(CDRNetworkPostureNone), @(CDRNetworkPostureNone), @(CDRNetworkChangeNone)],
        @[@(CDRNetworkPostureNone), @(CDRNetworkPostureClient), @(CDRNetworkChangeGained)],
        // A server-only addition is access too.
        @[@(CDRNetworkPostureNone), @(CDRNetworkPostureServer), @(CDRNetworkChangeGained)],
        @[@(CDRNetworkPostureNone), @(CDRNetworkPostureBoth), @(CDRNetworkChangeGained)],
        // Dropping the sandbox is gaining unrestricted access.
        @[@(CDRNetworkPostureNone), @(CDRNetworkPostureUnrestricted), @(CDRNetworkChangeGained)],
        // Already had access: adding more is not a crossing.
        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureBoth), @(CDRNetworkChangeNone)],
        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureClient), @(CDRNetworkChangeNone)],
        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureUnrestricted), @(CDRNetworkChangeNone)],
        @[@(CDRNetworkPostureUnrestricted), @(CDRNetworkPostureClient), @(CDRNetworkChangeNone)],
        // The good-news direction.
        @[@(CDRNetworkPostureUnrestricted), @(CDRNetworkPostureNone), @(CDRNetworkChangeLost)],
        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureNone), @(CDRNetworkChangeLost)],
        @[@(CDRNetworkPostureBoth), @(CDRNetworkPostureNone), @(CDRNetworkChangeLost)],
        // Unreadable postures err toward asking, and never claim good news.
        @[@(CDRNetworkPostureUnknown), @(CDRNetworkPostureClient), @(CDRNetworkChangeGained)],
        @[@(CDRNetworkPostureNone), @(CDRNetworkPostureUnknown), @(CDRNetworkChangeGained)],
        @[@(CDRNetworkPostureUnknown), @(CDRNetworkPostureNone), @(CDRNetworkChangeNone)],
        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureUnknown), @(CDRNetworkChangeNone)],
        @[@(CDRNetworkPostureUnknown), @(CDRNetworkPostureUnknown), @(CDRNetworkChangeNone)],
    ];
    for (NSArray<NSNumber *> *row in table) {
        XCTAssertEqual(CDRNetworkChangeBetween((CDRNetworkPosture)row[0].integerValue,
                                               (CDRNetworkPosture)row[1].integerValue),
                       (CDRNetworkChange)row[2].integerValue,
                       @"%@ → %@", CDRNetworkPostureDisplayName((CDRNetworkPosture)row[0].integerValue),
                       CDRNetworkPostureDisplayName((CDRNetworkPosture)row[1].integerValue));
    }
}

#pragma mark - The gate

- (CDRNetworkGateDecision)decideFrom:(CDRNetworkPosture)installed to:(CDRNetworkPosture)staged
                              policy:(BOOL)policy require:(BOOL)require exempts:(BOOL)exempts {
    return [CDRNetworkGate decisionForInstalledPosture:installed stagedPosture:staged hasPolicy:policy
                                           preferences:GatePrefs(require, exempts)];
}

- (void)testGateAsksOnlyWhenAccessIsGained {
    // Shipped defaults: approval required, a policy exempts.
    XCTAssertEqual([self decideFrom:CDRNetworkPostureNone to:CDRNetworkPostureClient policy:NO require:YES exempts:YES],
                   CDRNetworkGateDecisionAskWithoutPolicy);
    XCTAssertEqual([self decideFrom:CDRNetworkPostureNone to:CDRNetworkPostureClient policy:YES require:YES exempts:YES],
                   CDRNetworkGateDecisionNoAsk, @"a policy exempts the update when the user said so");
    XCTAssertEqual([self decideFrom:CDRNetworkPostureNone to:CDRNetworkPostureClient policy:YES require:YES exempts:NO],
                   CDRNetworkGateDecisionAskWithPolicy);
    // Server-only, and dropping the sandbox altogether.
    XCTAssertEqual([self decideFrom:CDRNetworkPostureNone to:CDRNetworkPostureServer policy:NO require:YES exempts:YES],
                   CDRNetworkGateDecisionAskWithoutPolicy);
    XCTAssertEqual([self decideFrom:CDRNetworkPostureNone to:CDRNetworkPostureUnrestricted policy:NO require:YES exempts:YES],
                   CDRNetworkGateDecisionAskWithoutPolicy);

    // Nothing gained: never asks.
    for (NSArray<NSNumber *> *pair in @[@[@(CDRNetworkPostureNone), @(CDRNetworkPostureNone)],
                                        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureBoth)],
                                        @[@(CDRNetworkPostureUnrestricted), @(CDRNetworkPostureUnrestricted)],
                                        // Good news is shown, never asked about.
                                        @[@(CDRNetworkPostureUnrestricted), @(CDRNetworkPostureNone)],
                                        @[@(CDRNetworkPostureClient), @(CDRNetworkPostureNone)]]) {
        for (NSNumber *policy in @[@NO, @YES]) {
            XCTAssertEqual([self decideFrom:(CDRNetworkPosture)pair[0].integerValue
                                         to:(CDRNetworkPosture)pair[1].integerValue
                                     policy:policy.boolValue require:YES exempts:NO],
                           CDRNetworkGateDecisionNoAsk);
        }
    }
}

- (void)testGateOffNeverAsks {
    for (NSNumber *policy in @[@NO, @YES]) {
        for (NSNumber *exempts in @[@NO, @YES]) {
            XCTAssertEqual([self decideFrom:CDRNetworkPostureNone to:CDRNetworkPostureBoth policy:policy.boolValue
                                    require:NO exempts:exempts.boolValue],
                           CDRNetworkGateDecisionNoAsk);
        }
    }
}

- (void)testInspectionSummarizesTheDiffAndFeedsTheGate {
    CDRInternetAccessPolicy *policy = [CDRInternetAccessPolicy policyWithPropertyList:@{
        @"Connections": @[@{@"Host": @"example.com", @"Purpose": @"Sync."}],
    } strings:nil];
    CDRNetworkInspection *gained = [[CDRNetworkInspection alloc]
        initWithInstalledVersion:@"0.4" stagedVersion:@"0.5"
           installedEntitlements:Entitlements(YES, NO, NO) stagedEntitlements:Entitlements(YES, YES, NO)
                    stagedPolicy:policy teamID:@"F252L9GUBW"];
    XCTAssertEqual(gained.change, CDRNetworkChangeGained);
    XCTAssertEqualObjects(gained.addedEntitlements, (@[CDREntitlementNetworkClient]));
    XCTAssertEqual(gained.removedEntitlements.count, 0u);
    XCTAssertTrue(gained.hasPolicy);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:gained preferences:GatePrefs(YES, NO)],
                   CDRNetworkGateDecisionAskWithPolicy);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:gained preferences:GatePrefs(YES, YES)],
                   CDRNetworkGateDecisionNoAsk);

    // Unsandboxed → sandboxed with no network: good news, with its diff.
    CDRNetworkInspection *lost = [[CDRNetworkInspection alloc]
        initWithInstalledVersion:@"0.9" stagedVersion:@"1.1"
           installedEntitlements:@{} stagedEntitlements:Entitlements(YES, NO, NO)
                    stagedPolicy:nil teamID:nil];
    XCTAssertEqual(lost.change, CDRNetworkChangeLost);
    XCTAssertEqualObjects(lost.addedEntitlements, (@[CDREntitlementAppSandbox]));
    XCTAssertFalse(lost.hasPolicy);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:lost preferences:GatePrefs(YES, NO)],
                   CDRNetworkGateDecisionNoAsk);

    // Entitlements that couldn't be read are Unknown, not "none".
    CDRNetworkInspection *unreadable = [[CDRNetworkInspection alloc]
        initWithInstalledVersion:@"1" stagedVersion:@"2" installedEntitlements:nil
              stagedEntitlements:Entitlements(YES, YES, NO) stagedPolicy:nil teamID:nil];
    XCTAssertEqual(unreadable.installedPosture, CDRNetworkPostureUnknown);
    XCTAssertEqual([CDRNetworkGate decisionForInspection:unreadable preferences:GatePrefs(YES, YES)],
                   CDRNetworkGateDecisionAskWithoutPolicy);
}

- (void)testAPolicyWithNothingToShowIsNoPolicy {
    CDRInternetAccessPolicy *empty = [CDRInternetAccessPolicy policyWithPropertyList:@{@"Connections": @[]} strings:nil];
    CDRNetworkInspection *inspection = [[CDRNetworkInspection alloc]
        initWithInstalledVersion:@"1" stagedVersion:@"2" installedEntitlements:Entitlements(YES, NO, NO)
              stagedEntitlements:Entitlements(YES, YES, NO) stagedPolicy:empty teamID:nil];
    XCTAssertFalse(inspection.hasPolicy);
    // Even with the exemption on: an empty policy explains nothing.
    XCTAssertEqual([CDRNetworkGate decisionForInspection:inspection preferences:GatePrefs(YES, YES)],
                   CDRNetworkGateDecisionAskWithoutPolicy);
}

#pragma mark - Internet Access Policy parser

- (void)testPolicyRowsFromTheFormatRealAppsShip {
    // Shapes taken from policies found in /Applications (see the recon doc):
    // literal text, keys into a .strings table, comma-separated hosts and
    // ports, a bare wildcard, an incoming connection.
    NSDictionary *plist = @{
        @"ApplicationDescription": @"IAP_APP_DESC",
        @"DeveloperName": @"Example Inc.",
        @"Website": @"https://example.com",
        @"Connections": @[
            @{@"Host": @"*", @"NetworkProtocol": @"TCP", @"Port": @"80, 443", @"IsIncoming": @NO,
              @"Purpose": @"Connects to servers you specify.", @"DenyConsequences": @"Nothing loads."},
            @{@"Host": @"*.example.net, example.org", @"NetworkProtocol": @"TCP", @"Port": @"443",
              @"Relevance": @"Essential", @"Purpose": @"IAP_UPDATE_PURPOSE"},
            @{@"Host": @"sync.example.com", @"IsIncoming": @YES, @"Port": @19186, @"Purpose": @"  Sync\nbetween   devices.  "},
            @{@"Host": @"quiet.example.com"},
        ],
    };
    NSDictionary *strings = @{@"IAP_APP_DESC": @"An example app.", @"IAP_UPDATE_PURPOSE": @"Checks for updates."};
    CDRInternetAccessPolicy *policy = [CDRInternetAccessPolicy policyWithPropertyList:plist strings:strings];

    XCTAssertEqualObjects(policy.applicationDescription, @"An example app.");
    XCTAssertEqualObjects([policy.rows valueForKey:@"subject"],
                          (@[@"Any server", @"*.example.net, example.org", @"sync.example.com", @"quiet.example.com"]));
    XCTAssertEqualObjects([policy.rows valueForKey:@"purpose"],
                          (@[@"Connects to servers you specify.", @"Checks for updates.",
                             @"Sync between devices.", @"No purpose given."]));
    XCTAssertEqualObjects(policy.rows[0].transport, @"TCP 80, 443");
    XCTAssertEqualObjects(policy.rows[2].transport, @"19186");
    XCTAssertNil(policy.rows[3].transport);
    XCTAssertFalse(policy.rows[0].incoming);
    XCTAssertTrue(policy.rows[2].incoming);
    XCTAssertEqual(policy.warnings.count, 0u);

    // Without the table, a key stays a key — the literal value is the fallback.
    XCTAssertEqualObjects([CDRInternetAccessPolicy policyWithPropertyList:plist strings:nil].rows[1].purpose,
                          @"IAP_UPDATE_PURPOSE");
}

- (void)testPolicyParserDropsWhatItCantShowAndSaysSo {
    NSMutableArray *many = [NSMutableArray array];
    for (NSUInteger i = 0; i < CDRInternetAccessPolicyMaxRows + 3; i++) {
        [many addObject:@{@"Host": [NSString stringWithFormat:@"h%lu.example.com", (unsigned long)i]}];
    }
    CDRInternetAccessPolicy *capped = [CDRInternetAccessPolicy policyWithPropertyList:@{@"Connections": many} strings:nil];
    XCTAssertEqual(capped.rows.count, CDRInternetAccessPolicyMaxRows);
    XCTAssertEqual(capped.warnings.count, 1u);

    CDRInternetAccessPolicy *messy = [CDRInternetAccessPolicy policyWithPropertyList:@{
        @"Connections": @[@"not a dictionary", @{@"Purpose": @"No host."}, @{@"Host": @""}, @{@"Host": @7},
                          @{@"Host": @"ok.example.com", @"Purpose": [@"" stringByPaddingToLength:900
                                                                                       withString:@"long " startingAtIndex:0]}],
        @"Services": @[@{@"Identifier": @"com.apple.MapKit", @"Purpose": @"Maps."}],
    } strings:nil];
    XCTAssertEqual(messy.rows.count, 1u);
    XCTAssertLessThanOrEqual(messy.rows.firstObject.purpose.length, 300u);
    // One warning for the four host-less entries, one for the service.
    XCTAssertEqual(messy.warnings.count, 2u);

    // Garbage is "no policy", never an error.
    for (id garbage in @[@"text", @[@1], @7, [NSNull null]]) {
        XCTAssertNil([CDRInternetAccessPolicy policyWithPropertyList:garbage strings:nil]);
    }
    XCTAssertNil([CDRInternetAccessPolicy policyWithPropertyList:nil strings:nil]);
    CDRInternetAccessPolicy *noConnections =
        [CDRInternetAccessPolicy policyWithPropertyList:@{@"Connections": @"none"} strings:nil];
    XCTAssertEqual(noConnections.rows.count, 0u);
    XCTAssertEqual(noConnections.warnings.count, 1u);
}

- (void)testPolicyIsReadFromABundlesResourcesInAnyOfTheThreeLayouts {
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-iap-%@", NSUUID.UUID.UUIDString]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *plist = @{@"Connections": @[@{@"Host": @"a.example.com", @"Purpose": @"KEY_A"}]};

    // Contents/Resources/InternetAccessPolicy.plist, with an English table.
    NSURL *plain = [root URLByAppendingPathComponent:@"Plain.app"];
    NSURL *resources = [plain URLByAppendingPathComponent:@"Contents/Resources"];
    [fm createDirectoryAtURL:[resources URLByAppendingPathComponent:@"en.lproj"]
 withIntermediateDirectories:YES attributes:nil error:NULL];
    [plist writeToURL:[resources URLByAppendingPathComponent:@"InternetAccessPolicy.plist"] atomically:YES];
    [@"\"KEY_A\" = \"Fetches A.\";\n" writeToURL:[resources URLByAppendingPathComponent:@"en.lproj/InternetAccessPolicy.strings"]
                                      atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CDRInternetAccessPolicy *policy = [CDRInternetAccessPolicy policyForBundleAtURL:plain];
    XCTAssertEqualObjects(policy.rows.firstObject.subject, @"a.example.com");
    XCTAssertEqualObjects(policy.rows.firstObject.purpose, @"Fetches A.");

    // Base.lproj (how Little Snitch itself ships it).
    NSURL *based = [root URLByAppendingPathComponent:@"Based.app"];
    NSURL *base = [based URLByAppendingPathComponent:@"Contents/Resources/Base.lproj"];
    [fm createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:NULL];
    [plist writeToURL:[base URLByAppendingPathComponent:@"InternetAccessPolicy.plist"] atomically:YES];
    XCTAssertEqual([CDRInternetAccessPolicy policyForBundleAtURL:based].rows.count, 1u);

    // JSON (seen in the wild).
    NSURL *jsonApp = [root URLByAppendingPathComponent:@"Json.app"];
    NSURL *jsonResources = [jsonApp URLByAppendingPathComponent:@"Contents/Resources"];
    [fm createDirectoryAtURL:jsonResources withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSJSONSerialization dataWithJSONObject:plist options:0 error:NULL]
        writeToURL:[jsonResources URLByAppendingPathComponent:@"InternetAccessPolicy.json"] atomically:YES];
    XCTAssertEqual([CDRInternetAccessPolicy policyForBundleAtURL:jsonApp].rows.count, 1u);

    // None, and an unreadable one.
    NSURL *bare = [root URLByAppendingPathComponent:@"Bare.app"];
    NSURL *bareResources = [bare URLByAppendingPathComponent:@"Contents/Resources"];
    [fm createDirectoryAtURL:bareResources withIntermediateDirectories:YES attributes:nil error:NULL];
    XCTAssertNil([CDRInternetAccessPolicy policyForBundleAtURL:bare]);
    [@"not a plist" writeToURL:[bareResources URLByAppendingPathComponent:@"InternetAccessPolicy.plist"]
                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNil([CDRInternetAccessPolicy policyForBundleAtURL:bare]);

    [fm removeItemAtURL:root error:NULL];
}

#pragma mark - Entitlement reader, against real signed bundles

- (void)testHostAppIsNotSandboxedSoItsPostureIsUnrestricted {
    // Conductor itself: signed, hardened, not sandboxed.
    NSString *team = nil;
    NSDictionary *entitlements = [CDRBundleInspector entitlementsForBundleAtURL:NSBundle.mainBundle.bundleURL
                                                                         teamID:&team];
    XCTAssertNotNil(entitlements);
    XCTAssertEqualObjects(team, @"F252L9GUBW");
    XCTAssertNil(entitlements[CDREntitlementAppSandbox]);
    XCTAssertEqual([CDRBundleInspector networkPostureForBundleAtURL:NSBundle.mainBundle.bundleURL],
                   CDRNetworkPostureUnrestricted);
}

- (void)testSystemAppsReadAsTheirRealPostures {
    // Stickies is sandboxed with no network entitlement; Safari is
    // sandboxed with network.client.
    NSURL *stickies = [NSURL fileURLWithPath:@"/System/Applications/Stickies.app"];
    NSURL *safari = [NSURL fileURLWithPath:@"/Applications/Safari.app"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:stickies.path] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:safari.path]) {
        XCTSkip(@"needs Stickies.app and Safari.app");
    }
    XCTAssertEqual([CDRBundleInspector networkPostureForBundleAtURL:stickies], CDRNetworkPostureNone);
    CDRNetworkPosture safariPosture = [CDRBundleInspector networkPostureForBundleAtURL:safari];
    XCTAssertTrue(safariPosture == CDRNetworkPostureClient || safariPosture == CDRNetworkPostureBoth);
}

- (void)testUnsignedAndMissingBundlesAreUnknownNeverNone {
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"cdr-unsigned-%@", NSUUID.UUID.UUIDString]];
    NSURL *app = [root URLByAppendingPathComponent:@"Unsigned.app"];
    [[NSFileManager defaultManager] createDirectoryAtURL:[app URLByAppendingPathComponent:@"Contents/MacOS"]
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [@{@"CFBundleIdentifier": @"com.example.unsigned", @"CFBundleExecutable": @"Unsigned"}
        writeToURL:[app URLByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:@"/bin/echo"]
                                            toURL:[app URLByAppendingPathComponent:@"Contents/MacOS/Unsigned"] error:NULL];
    // /bin/echo carries Apple's signature as a file; as this bundle's main
    // executable it does not make the bundle a validly identified one for
    // our purposes — what matters is that nothing here reads as "None".
    CDRNetworkPosture posture = [CDRBundleInspector networkPostureForBundleAtURL:app];
    XCTAssertNotEqual(posture, CDRNetworkPostureNone);

    XCTAssertNil([CDRBundleInspector entitlementsForBundleAtURL:[root URLByAppendingPathComponent:@"Missing.app"]
                                                        teamID:NULL]);
    XCTAssertEqual([CDRBundleInspector networkPostureForBundleAtURL:[root URLByAppendingPathComponent:@"Missing.app"]],
                   CDRNetworkPostureUnknown);
    [[NSFileManager defaultManager] removeItemAtURL:root error:NULL];
}

@end
