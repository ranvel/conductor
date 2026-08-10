# Conductor — Project Index

> Auto-maintained by Claude. Last updated: 2026-08-10

## Project Structure

### / (Root)
- `project-index.md` — This file
- `CLAUDE.md` — AI onboarding context and security invariants
- `README.md` — Project readme
- `LICENSE.md` — License
- `.gitignore` — Git ignore rules

### /Conductor/
App-level wiring: AppDelegate, UI controllers, and the menu bar app (M3).

- `Conductor/main.m` — NSApplicationMain entry point
- `Conductor/AppDelegate.h` — NSApplicationDelegate interface
- `Conductor/AppDelegate.m` — Startup wiring: scanner, scheduler, dev mode, UI controllers
- `Conductor/CDRAppearanceSettings.h` — Menu bar / Dock visibility user defaults
- `Conductor/CDRAppearanceSettings.m` — Implementation of visibility settings and fallbacks
- `Conductor/CDRAppRowModel.h` — Per-app presentation state shared by both UI surfaces
- `Conductor/CDRAppRowModel.m` — Row model logic: state derivation, badge contribution
- `Conductor/CDRIgnoreList.h` — Per-app ignore list backed by NSUserDefaults
- `Conductor/CDRIgnoreList.m` — Ignore list read/write helpers
- `Conductor/CDRMenuBarController.h` — NSStatusItem menu rendering row models, dev-mode badge
- `Conductor/CDRMenuBarController.m` — Menu bar UI: menu construction, icon variants, actions
- `Conductor/CDRNotificationPresenter.h` — UNUserNotification delivery for background results
- `Conductor/CDRNotificationPresenter.m` — Notification categories, actions, and gating logic
- `Conductor/CDRScanScheduler.h` — Periodic background scan timer (manual/6h/daily/weekly)
- `Conductor/CDRScanScheduler.m` — Timer scheduling and cadence defaults persistence
- `Conductor/CDRSettingsWindowController.h` — Settings window: login, visibility, soak, cadence, ignores
- `Conductor/CDRSettingsWindowController.m` — Settings UI construction and defaults binding
- `Conductor/CDRSharedLog.h` — Unified os_log + in-memory ring buffer for activity log
- `Conductor/CDRSharedLog.m` — Log sink implementation with append notification
- `Conductor/CDRStatusWindowController.h` — Windowed UI rendering row models and activity log
- `Conductor/CDRStatusWindowController.m` — Status window layout, row views, log display
- `Conductor/CDRUpdateController.h` — App-level coordinator: discovery, checks, decisions, operations
- `Conductor/CDRUpdateController.m` — Update orchestration: scan → fetch → decide → present
- `Conductor/CDRUpdatePresenting.h` — Protocol seam between controller and UI (modal vs passive)

### /Conductor/Engine/
The update engine: single-purpose classes composed by CDRUpdateOperation.

- `Conductor/Engine/CDRAppRegistration.h` — One managed app's identity and conductor.json URLs
- `Conductor/Engine/CDRAppRegistration.m` — Registration parsing from bundle + conductor.json
- `Conductor/Engine/CDRAppScanner.h` — Discovers apps embedding conductor.json in /Applications
- `Conductor/Engine/CDRAppScanner.m` — Shallow directory scan, self-exclusion, parse-error skip
- `Conductor/Engine/CDRAppUpdateState.h` — Per-app deferral/retraction state (soak clock, notification memory)
- `Conductor/Engine/CDRAppUpdateState.m` — Immutable state snapshots and stateBy… mutation methods
- `Conductor/Engine/CDRArtifactDownloader.h` — Downloads artifact to staging with optional SHA-256 check
- `Conductor/Engine/CDRArtifactDownloader.m` — NSURLSession download, checksum verification
- `Conductor/Engine/CDRArtifactStager.h` — Staging directory management and zip/DMG extraction
- `Conductor/Engine/CDRArtifactStager.m` — Content-sniffed extraction, single .app discovery
- `Conductor/Engine/CDRAtomicSwapper.h` — Sole /Applications mutation: atomic same-volume replace
- `Conductor/Engine/CDRAtomicSwapper.m` — NSFileManager replaceItem, backup to Trash
- `Conductor/Engine/CDRCodeSignature.h` — Team ID capture, pinned validation, and XPC audit-token validation
- `Conductor/Engine/CDRCodeSignature.m` — Security.framework SecCode APIs, anchor requirement, audit-token peer check
- `Conductor/Engine/CDRHelperProtocol.h` — Shared XPC protocol for privileged helper (one method: swap)
- `Conductor/Engine/CDRPrivilegedHelperManager.h` — SMAppService daemon lifecycle and XPC swap proxy
- `Conductor/Engine/CDRPrivilegedHelperManager.m` — Helper registration, connection management, privileged swap
- `Conductor/Engine/CDRDevModeSession.h` — Session-only transport relaxation for one bundle ID
- `Conductor/Engine/CDRDevModeSession.m` — Launch argument parsing, HTTP allowance per bundle
- `Conductor/Engine/CDRErrors.h` — CDRErrorDomain codes grouped by hundreds (1xx–6xx)
- `Conductor/Engine/CDRErrors.m` — CDRError() helper for localized error construction
- `Conductor/Engine/CDRManifest.h` — Vendor-served manifest model with urgency enum
- `Conductor/Engine/CDRManifest.m` — JSON parsing, format version gate, retraction flag
- `Conductor/Engine/CDRManifestFetcher.h` — Manifest fetch with primary-wins/fallback-on-unreachable
- `Conductor/Engine/CDRManifestFetcher.m` — NSURLSession fetch, transport enforcement, bundle ID match
- `Conductor/Engine/CDRNotarizationCheck.h` — Apple notarization verification via spctl shell-out
- `Conductor/Engine/CDRNotarizationCheck.m` — NSTask spctl invocation and exit-code interpretation
- `Conductor/Engine/CDRQuarantine.h` — Recursive com.apple.quarantine xattr removal post-verify
- `Conductor/Engine/CDRQuarantine.m` — xattr enumeration and removal, provenance left alone
- `Conductor/Engine/CDRQuitMonitor.h` — Running-app detection and polite terminate with timeout
- `Conductor/Engine/CDRQuitMonitor.m` — NSWorkspace termination observation, grace period
- `Conductor/Engine/CDRUpdateOperation.h` — Serial-queue phase machine orchestrating the full update
- `Conductor/Engine/CDRUpdateOperation.m` — Phase transitions: Fetch→Download→Extract→Verify→Quit→Swap→Finish
- `Conductor/Engine/CDRUpdatePolicy.h` — Soak duration setting and per-app update decisions
- `Conductor/Engine/CDRUpdatePolicy.m` — Decision logic: downgrade refusal, soak gate, urgency bypass
- `Conductor/Engine/CDRUpdateStateStore.h` — Plist persistence of all per-app update memory
- `Conductor/Engine/CDRUpdateStateStore.m` — Load/save with retention TTL, first_seen pruning
- `Conductor/Engine/CDRVersion.h` — Numeric-aware dotted version string comparison
- `Conductor/Engine/CDRVersion.m` — Component-wise compare, short version + build ordering

### /CDRPrivilegedHelper/
Root-level XPC daemon for escalated bundle swaps (SMAppService LaunchDaemon).

- `CDRPrivilegedHelper/main.m` — XPC listener, audit-token client validation, atomic swap as root
- `CDRPrivilegedHelper/com.ranvel.Conductor.PrivilegedHelper.plist` — LaunchDaemon definition (on-demand MachServices)

### /ConductorTests/
Unit and integration tests.

- `ConductorTests/ConductorTests.m` — Xcode template test stub (empty)
- `ConductorTests/CDRAppRegistrationTests.m` — Tests for conductor.json parsing and registration
- `ConductorTests/CDRAppRowModelTests.m` — Tests for row model state derivation
- `ConductorTests/CDRArtifactStagerTests.m` — Tests for zip/DMG extraction and staging
- `ConductorTests/CDRAtomicSwapperTests.m` — Tests for atomic replace and backup-to-Trash
- `ConductorTests/CDRCodeSignatureTests.m` — Tests for Team ID capture and pinned validation
- `ConductorTests/CDRDevModeSessionTests.m` — Tests for dev-mode argument parsing and HTTP policy
- `ConductorTests/CDRIgnoreListTests.m` — Tests for ignore list read/write
- `ConductorTests/CDRManifestTests.m` — Tests for manifest JSON parsing and edge cases
- `ConductorTests/CDRNotificationGateTests.m` — Tests for notification gating logic
- `ConductorTests/CDRQuarantineTests.m` — Tests for quarantine xattr stripping
- `ConductorTests/CDRQuitMonitorTests.m` — Tests for quit detection and termination
- `ConductorTests/CDRRetractionDrillIntegrationTests.m` — Integration test for retraction state transitions
- `ConductorTests/CDRScanSchedulerTests.m` — Tests for scan cadence and timer scheduling
- `ConductorTests/CDRUpdateOperationIntegrationTests.m` — End-to-end engine test against local HTTP server
- `ConductorTests/CDRUpdatePolicyTests.m` — Tests for soak gate, downgrade refusal, urgency bypass
- `ConductorTests/CDRUpdateStateStoreTests.m` — Tests for plist persistence and retention TTL
- `ConductorTests/CDRVersionTests.m` — Tests for version string comparison

### /ConductorUITests/
- `ConductorUITests/ConductorUITests.m` — UI test stub (empty)
- `ConductorUITests/ConductorUITestsLaunchTests.m` — Launch test stub (empty)

### /docs/
Design-authority specs; code follows these, not vice versa.

- `docs/spec.md` — Public specification v1 (draft for M4 review)
- `docs/replace-flow.md` — Security core: verify → stage → quit → swap → dequarantine
- `docs/dev-mode.md` — Dev-mode transport relaxation (HTTP only, never verification)
- `docs/deferral.md` — Per-app soak/deferral state model (M2)
- `docs/retraction.md` — Retraction state model and loudness rules (M2)
- `docs/roadmap.md` — Milestone numbering and feature plan
- `docs/MUW-145.md` — Implementation note (MUW-145)

### /TestHarness/
End-to-end test artifacts for dev-mode integration testing.

- `TestHarness/build-testee.sh` — Builds, signs, and packages ConductorTestee v1.0/v1.1
- `TestHarness/testee-main.m` — Minimal AppKit app that displays its version and quits politely
- `TestHarness/.gitignore` — Ignores build intermediates

### /TestHarness/einval-investigation/
VM-targeted harness for diagnosing the EINVAL swap failure on macOS Tahoe.

- `TestHarness/einval-investigation/Makefile` — Builds all C/ObjC harnesses via clang
- `TestHarness/einval-investigation/run-all.sh` — Master runner: executes experiments 1–12, collects results
- `TestHarness/einval-investigation/setup-bundles.sh` — Creates test .app bundles at production paths
- `TestHarness/einval-investigation/teardown.sh` — Removes only test bundles (marker-gated safety)
- `TestHarness/einval-investigation/results-template.md` — Blank results table for recording outcomes
- `TestHarness/einval-investigation/lib/harness-common.h` — REPORT() macro, errno names, shared path constants
- `TestHarness/einval-investigation/lib/bundle-factory.h` — API for creating minimal .app bundles
- `TestHarness/einval-investigation/lib/bundle-factory.c` — Bundle creation with .einval-test-bundle marker
- `TestHarness/einval-investigation/harnesses/01-renamex-swap.c` — Exp 1: direct renamex_np(RENAME_SWAP)
- `TestHarness/einval-investigation/harnesses/02-rename-plain.c` — Exp 2: plain rename(2), key diagnostic
- `TestHarness/einval-investigation/harnesses/03-inspect-fs.sh` — Exp 3: device IDs, symlinks, firmlinks
- `TestHarness/einval-investigation/harnesses/04-inspect-xattr.sh` — Exp 4: xattrs, com.apple.macl, ACLs
- `TestHarness/einval-investigation/harnesses/05-two-step-move.c` — Exp 5: Sparkle-style rename with rollback
- `TestHarness/einval-investigation/harnesses/06-delete-then-move.m` — Exp 6: NSFileManager remove+move (Mysk path)
- `TestHarness/einval-investigation/harnesses/07-ditto-copy.sh` — Exp 7: ditto copy after remove
- `TestHarness/einval-investigation/harnesses/08-cli-helper.m` — Exp 8: strategies via NSTask/posix_spawn
- `TestHarness/einval-investigation/harnesses/09-shell-wrapper.sh` — Exp 9: strategies via /bin/sh
- `TestHarness/einval-investigation/harnesses/10-sudo-variants.sh` — Exp 10: key experiments with sudo
- `TestHarness/einval-investigation/harnesses/11-remove-vs-replace.m` — Exp 11: removeItem vs replaceItem isolation
- `TestHarness/einval-investigation/harnesses/12-tcc-toggle-notes.md` — Exp 12: manual App Management toggle procedure

### /icon/
App icon source assets and generation tooling.

- `icon/conductrix.png` — Source icon artwork
- `icon/conductor-macOS-Default-1024x1024@1x.png` — 1024px rendered icon
- `icon/icon-maker/make-icons.sh` — Generates iconset from 1024px source via sips
- `icon/icon-maker/Icon1024.png` — 1024px input for iconset generation
- `icon/icon-maker/MyIcon.icns` — Generated icns bundle

### /Conductor.xcodeproj/
- `Conductor.xcodeproj/project.pbxproj` — Xcode project file (synchronized file groups)
