//
//  CDRSwapEscalationTests.m
//  ConductorTests
//
//  Unit coverage for the swap-escalation decision in CDRUpdateOperation: when
//  the unprivileged swap fails, does the operation escalate to the privileged
//  helper on the right errors, register lazily, surface the approval prompt as
//  a clean failure, and converge on the shared post-swap tail regardless of
//  which path performed the swap?
//
//  Driven with a fake swapper and a fake helper manager (no real XPC, no real
//  /Applications) and by calling -stepSwap: directly via the test seam, so the
//  fetch → download → verify pipeline is bypassed. Leaving stagedShortVersion
//  nil (its default) keeps stepSwap's freshness re-guard a no-op.
//

#import <XCTest/XCTest.h>
#import "CDRUpdateOperation.h"
#import "CDRUpdateOperation+Testing.h"
#import "CDRAtomicSwapper.h"
#import "CDRPrivilegedHelperManager.h"
#import "CDRAppRegistration.h"
#import "CDRManifest.h"
#import "CDRDevModeSession.h"
#import "CDRErrors.h"

static NSString * const kEscBundleID = @"com.ranvel.escalation-test";

#pragma mark - Fakes

/// Stand-in registration. The swap step only reads bundleID and appURL; a
/// non-existent appURL keeps the freshness re-guard a no-op (its Info.plist
/// read returns nil).
@interface CDRFakeRegistration : CDRAppRegistration
@end
@implementation CDRFakeRegistration
- (NSURL *)appURL { return [NSURL fileURLWithPath:@"/private/tmp/CDRSwapEscalation/DoesNotExist.app"]; }
- (NSString *)bundleID { return kEscBundleID; }
- (NSString *)installedShortVersion { return @"1.0"; }
@end

/// Fails every unprivileged swap with a scripted error. Overrides the trash so
/// the success-path tail can run without touching NSWorkspace.
@interface CDRFakeSwapper : CDRAtomicSwapper
@property (nonatomic) NSError *scriptedError;   // returned from the swap attempt
@property (nonatomic) BOOL swapAttempted;
@property (nonatomic) BOOL trashAttempted;
@end
@implementation CDRFakeSwapper
- (BOOL)swapInstalledAppAtURL:(NSURL *)installedURL
           withStagedAppAtURL:(NSURL *)stagedURL
                     bundleID:(NSString *)bundleID
                    backupURL:(NSURL *_Nullable *_Nullable)backupOut
                        error:(NSError **)error {
    self.swapAttempted = YES;
    if (error) *error = self.scriptedError;
    return NO;
}
- (void)trashDisplacedBundleAtURL:(NSURL *)backupURL
                       completion:(void (^)(NSError *_Nullable))completion {
    self.trashAttempted = YES;
    completion(nil);
}
@end

/// Scriptable helper manager — no SMAppService, no XPC. `installed` doubles as
/// the isHelperInstalled answer and is flipped YES by a successful install.
@interface CDRFakeHelperManager : CDRPrivilegedHelperManager
@property (nonatomic) BOOL installed;         // isHelperInstalled
@property (nonatomic) BOOL installSucceeds;   // installHelperWithError: result
@property (nonatomic) NSError *installError;  // handed back when install fails
@property (nonatomic) BOOL swapSucceeds;      // privileged swap result
@property (nonatomic) NSURL *swapBackupURL;   // backup returned on privileged success
@property (nonatomic) NSError *swapError;     // returned on privileged failure
@property (nonatomic) BOOL installCalled;
@property (nonatomic) BOOL swapCalled;
@end
@implementation CDRFakeHelperManager
- (BOOL)isHelperInstalled { return self.installed; }
- (BOOL)installHelperWithError:(NSError **)error {
    self.installCalled = YES;
    if (self.installSucceeds) { self.installed = YES; return YES; }
    if (error) *error = self.installError;
    return NO;
}
- (void)swapBundleAtURL:(NSURL *)installedURL
        withStagedAtURL:(NSURL *)stagedURL
             completion:(void (^)(BOOL, NSURL *_Nullable, NSError *_Nullable))completion {
    self.swapCalled = YES;
    if (self.swapSucceeds) {
        completion(YES, self.swapBackupURL, nil);
    } else {
        completion(NO, nil, self.swapError);
    }
}
@end

#pragma mark - Delegate recorder

@interface CDREscalationDelegate : NSObject <CDRUpdateOperationDelegate>
@property (nonatomic) NSMutableArray<NSNumber *> *phases;
@property (nonatomic) NSMutableArray<NSString *> *logs;
@property (nonatomic, nullable) NSError *finishError;
@property (nonatomic) XCTestExpectation *finished;
@end
@implementation CDREscalationDelegate
- (instancetype)init {
    self = [super init];
    _phases = [NSMutableArray array];
    _logs = [NSMutableArray array];
    return self;
}
- (void)updateOperation:(CDRUpdateOperation *)op didEnterPhase:(CDRUpdatePhase)phase {
    [self.phases addObject:@(phase)];
}
- (void)updateOperation:(CDRUpdateOperation *)op logMessage:(NSString *)message {
    [self.logs addObject:message];
}
- (void)updateOperation:(CDRUpdateOperation *)op
    requestsQuitDecisionFor:(NSArray<NSRunningApplication *> *)apps
                      reply:(void (^)(CDRQuitDecision))reply {
    reply(CDRQuitDecisionQuitAndUpdate);
}
- (void)updateOperation:(CDRUpdateOperation *)op
     didFinishWithError:(NSError *)error
       appWasQuitByFlow:(BOOL)wasQuit {
    self.finishError = error;
    [self.finished fulfill];
}
- (BOOL)sawPhase:(CDRUpdatePhase)phase { return [self.phases containsObject:@(phase)]; }
@end

#pragma mark - Tests

@interface CDRSwapEscalationTests : XCTestCase
@property (nonatomic) CDRUpdateOperation *op;   // retained across the async wait
@property (nonatomic) CDREscalationDelegate *delegate;
@end

@implementation CDRSwapEscalationTests

- (void)setUp {
    self.continueAfterFailure = NO;
}

/// Wire an operation with the two fakes and a fresh recorder delegate. The
/// manifest/session are real but inert — the swap step never touches them.
- (CDREscalationDelegate *)driveStepSwapWithSwapper:(CDRFakeSwapper *)swapper
                                      helperManager:(CDRFakeHelperManager *)helper {
    CDREscalationDelegate *delegate = [[CDREscalationDelegate alloc] init];
    delegate.finished = [self expectationWithDescription:@"operation finished"];

    NSString *json = @"{\"conductor_manifest\":1,\"bundle_id\":\"com.ranvel.escalation-test\","
                      "\"version\":\"2.0\",\"url\":\"https://example.com/a.zip\"}";
    CDRManifest *manifest = [CDRManifest manifestWithData:
        [json dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
    XCTAssertNotNil(manifest);
    CDRDevModeSession *session = [CDRDevModeSession sessionFromArguments:@[@"conductor"] error:NULL];
    XCTAssertNotNil(session);

    CDRUpdateOperation *op = [[CDRUpdateOperation alloc]
        initWithRegistration:[[CDRFakeRegistration alloc] init]
                    manifest:manifest
                     session:session
                    delegate:delegate];
    op.swapper = swapper;
    op.helperManager = helper;

    // Hold strong refs: the operation keeps the delegate weakly, and the
    // escalation completion resumes asynchronously on the work queue.
    self.op = op;
    self.delegate = delegate;

    [op stepSwap:[NSURL fileURLWithPath:@"/private/tmp/CDRSwapEscalation/Staged.app"]];
    [self waitForExpectations:@[delegate.finished] timeout:5];
    return delegate;
}

// (a) Escalation-eligible failure, helper not yet approved: the operation asks
//     to register, install reports RequiresApproval, and we fail with that
//     actionable error without ever attempting the privileged swap.
- (void)testPermissionDeniedWithUnapprovedHelperFailsWithApprovalError {
    CDRFakeSwapper *swapper = [[CDRFakeSwapper alloc] init];
    swapper.scriptedError = CDRError(CDRErrorPermissionDenied, kEscBundleID, nil, nil);

    NSError *approval = CDRError(CDRErrorPermissionDenied, nil, nil,
        @{NSLocalizedDescriptionKey: @"The privileged helper requires approval in "
                                      "System Settings › Login Items."});
    CDRFakeHelperManager *helper = [[CDRFakeHelperManager alloc] init];
    helper.installed = NO;
    helper.installSucceeds = NO;
    helper.installError = approval;

    CDREscalationDelegate *d = [self driveStepSwapWithSwapper:swapper helperManager:helper];

    XCTAssertTrue(helper.installCalled, @"registration should have been attempted");
    XCTAssertFalse(helper.swapCalled, @"privileged swap must not run before approval");
    XCTAssertNotNil(d.finishError);
    XCTAssertEqualObjects(d.finishError.domain, CDRErrorDomain);
    XCTAssertEqual(d.finishError.code, CDRErrorPermissionDenied);
    XCTAssertEqualObjects(d.finishError, approval, @"should fail with the install error verbatim");
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseSwapping]);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseFailed]);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseFinishing]);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseDone]);
}

// (b) Escalation-eligible failure, helper already installed, privileged swap
//     succeeds with a displaced bundle: no re-registration, the swap runs, the
//     shared tail trashes the backup and the operation succeeds.
- (void)testPermissionDeniedWithInstalledHelperSucceedsViaPrivilegedSwap {
    CDRFakeSwapper *swapper = [[CDRFakeSwapper alloc] init];
    swapper.scriptedError = CDRError(CDRErrorPermissionDenied, kEscBundleID, nil, nil);

    CDRFakeHelperManager *helper = [[CDRFakeHelperManager alloc] init];
    helper.installed = YES;
    helper.swapSucceeds = YES;
    helper.swapBackupURL = [NSURL fileURLWithPath:@"/private/tmp/CDRSwapEscalation/displaced.app"];

    CDREscalationDelegate *d = [self driveStepSwapWithSwapper:swapper helperManager:helper];

    XCTAssertFalse(helper.installCalled, @"an installed helper needs no registration");
    XCTAssertTrue(helper.swapCalled);
    XCTAssertTrue(swapper.trashAttempted, @"the displaced bundle should be trashed via the shared tail");
    XCTAssertNil(d.finishError);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseFinishing]);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseDone]);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseFailed]);
}

// (c) Escalation-eligible failure, helper installed, privileged swap fails: we
//     fail with the helper's error, no retry loop.
- (void)testPrivilegedSwapFailureSurfacesHelperError {
    CDRFakeSwapper *swapper = [[CDRFakeSwapper alloc] init];
    swapper.scriptedError = CDRError(CDRErrorPermissionDenied, kEscBundleID, nil, nil);

    NSError *helperFailure = CDRError(CDRErrorSwapFailed, kEscBundleID, nil,
        @{NSLocalizedDescriptionKey: @"Privileged swap failed."});
    CDRFakeHelperManager *helper = [[CDRFakeHelperManager alloc] init];
    helper.installed = YES;
    helper.swapSucceeds = NO;
    helper.swapError = helperFailure;

    CDREscalationDelegate *d = [self driveStepSwapWithSwapper:swapper helperManager:helper];

    XCTAssertTrue(helper.swapCalled);
    XCTAssertEqualObjects(d.finishError, helperFailure);
    XCTAssertEqual(d.finishError.code, CDRErrorSwapFailed);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseFailed]);
    XCTAssertFalse([d sawPhase:CDRUpdatePhaseDone]);
}

// (d) A swap failure that privilege can't be expected to fix (plain
//     CDRErrorSwapFailed, no permission code and no NSFileWriteUnknownError in
//     the chain) must NOT escalate — the helper is never touched and the
//     original error is surfaced. This is the guardrail against escalating on,
//     e.g., a corrupt staged bundle.
- (void)testNonEscalatableErrorDoesNotTouchHelper {
    NSError *diskError = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteOutOfSpaceError userInfo:nil];
    CDRFakeSwapper *swapper = [[CDRFakeSwapper alloc] init];
    swapper.scriptedError = CDRError(CDRErrorSwapFailed, kEscBundleID, diskError, nil);

    CDRFakeHelperManager *helper = [[CDRFakeHelperManager alloc] init];
    helper.installed = YES;   // even though it's available, we must not use it

    CDREscalationDelegate *d = [self driveStepSwapWithSwapper:swapper helperManager:helper];

    XCTAssertFalse(helper.installCalled);
    XCTAssertFalse(helper.swapCalled, @"a non-permission swap failure must not escalate");
    XCTAssertEqualObjects(d.finishError, swapper.scriptedError);
    XCTAssertEqual(d.finishError.code, CDRErrorSwapFailed);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseFailed]);
}

// (e) The regression from the field report: the TCC/App-Management denial
//     classified as CDRErrorSwapFailed but carrying NSFileWriteUnknownError
//     (NSCocoaErrorDomain 512) in its underlying chain MUST escalate, even
//     though the top-level code is not CDRErrorPermissionDenied.
- (void)testUnknownWriteErrorInChainEscalates {
    NSError *tcc = [NSError errorWithDomain:NSCocoaErrorDomain
                                       code:NSFileWriteUnknownError userInfo:nil];
    CDRFakeSwapper *swapper = [[CDRFakeSwapper alloc] init];
    swapper.scriptedError = CDRError(CDRErrorSwapFailed, kEscBundleID, tcc, nil);

    CDRFakeHelperManager *helper = [[CDRFakeHelperManager alloc] init];
    helper.installed = YES;
    helper.swapSucceeds = YES;   // helper can fix it once escalated

    CDREscalationDelegate *d = [self driveStepSwapWithSwapper:swapper helperManager:helper];

    XCTAssertTrue(helper.swapCalled, @"a 512 in the chain should escalate to the helper");
    XCTAssertNil(d.finishError);
    XCTAssertTrue([d sawPhase:CDRUpdatePhaseDone]);
}

@end
