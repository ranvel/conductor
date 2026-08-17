//
//  CDRUpdateOperation+Testing.h
//  ConductorTests
//
//  Test-only seam. `swapper` and `helperManager` are private class-extension
//  properties of CDRUpdateOperation; their accessors are synthesized in the
//  main implementation. Re-declaring them here lets a test substitute a fake
//  collaborator without any production API change. `stepSwap:` is re-declared
//  so the escalation tests can drive the swap phase directly, bypassing the
//  fetch → download → verify pipeline.
//
//  No @implementation of this category exists — the methods live on the main
//  class, so there is nothing to define here.
//

#import "CDRUpdateOperation.h"

@class CDRAtomicSwapper;
@class CDRPrivilegedHelperManager;

@interface CDRUpdateOperation (Testing)

@property (nonatomic) CDRAtomicSwapper *swapper;
@property (nonatomic) CDRPrivilegedHelperManager *helperManager;

/// §5 swap step — normally reached only through the pipeline on the work queue.
- (void)stepSwap:(NSURL *)stagedApp;

@end
