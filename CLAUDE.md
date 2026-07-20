# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Conductor is a standalone macOS updater for third-party apps: it discovers apps
that embed a `conductor.json`, fetches their manifests, and atomically replaces
their bundles after verifying them against Apple's PKI (Team ID pinning — no
vendor keys, no Sparkle-style EdDSA). Objective-C, AppKit, prefix `CDR`.

## Authoritative docs — read before touching the engine

The specs in `docs/` are design authority; code follows them, not vice versa.
When a change conflicts with a spec, raise it rather than silently diverging.

- `docs/replace-flow.md` — the security core: verify → stage → quit → swap →
  dequarantine, Team ID pinning rationale, the "no vendor hooks, ever" rule.
- `docs/dev-mode.md` — `--dev-mode <bundle-id>` relaxes transport (HTTP) only,
  never verification; session-only by construction.
- `docs/deferral.md` / `docs/retraction.md` — the per-app state model (M2,
  not yet implemented; parsing hooks like the urgency enum already exist).
- `docs/roadmap.md` — milestone numbering (M1 done: the engine; M2 next:
  deferral/retraction state).

## Security invariants (load-bearing; do not "fix")

- The atomic swap in `CDRAtomicSwapper` is the **sole mutation of
  /Applications** in the whole flow — quarantine is stripped on the *staged*
  bundle pre-swap for exactly this reason. Any failure anywhere must leave the
  installed app untouched.
- Downgrade refusal reads versions from the **staged bundle's Info.plist**,
  never from the manifest — the manifest is unauthenticated by design and must
  never become a security input (it only says *where* to look).
- Staging lives at `/Applications/.conductor-staging/<bundle-id>/`, next to
  the destination, so the swap is same-volume/atomic *by construction*. Do not
  move it to NSTemporaryDirectory().
- `CDRDevModeSession.allowsURL:forBundleID:` is the only place HTTP is ever
  permitted. Keep it that way.
- TCC grants survive updates because bundle ID + signing identity are verified
  unchanged — there is deliberately nothing to do post-swap; don't add it.
- Validation flags live in one constant (`kCDRValidationFlags` in
  `CDRCodeSignature.m`) so `kSecCSCheckNestedCode` can be enabled in one line
  (deferred to M5, see roadmap).

## Architecture

`CDRUpdateOperation` (Conductor/Engine/) is the orchestrator — a serial-queue
phase machine (Fetch → Download → Extract → Verify → AwaitQuit → Swap →
Finish) that owns cleanup and composes the single-purpose classes around it:
scanner/registration (discovery), manifest+fetcher (primary-wins,
fallback-on-unreachability-only), downloader (into staging, optional sha256),
stager (zip/DMG by content sniffing), code-signature (anchor capture + pinned
validation), notarization (spctl shell-out, confined to one class), quarantine,
quit monitor (polite terminate only, never force), swapper. All errors are
`CDRErrorDomain` (`CDRErrors.h`, grouped by hundreds); build them via the
`CDRError()` helper so localized copy stays centralized.

`AppDelegate` wires a milestone-grade status window (`CDRStatusWindowController`)
— it is scaffolding, replaced by a menu bar app in M3.

The Xcode project uses synchronized file groups: new files under `Conductor/`
or `ConductorTests/` join their targets automatically — never edit the pbxproj
to add files.

## Build & test

```sh
xcodebuild build -scheme Conductor -destination 'platform=macOS,arch=arm64'
xcodebuild test  -scheme Conductor -destination 'platform=macOS,arch=arm64' -only-testing:ConductorTests

# Single class / single test:
xcodebuild test -scheme Conductor -destination 'platform=macOS,arch=arm64' \
  -only-testing:ConductorTests/CDRVersionTests
xcodebuild test -scheme Conductor -destination 'platform=macOS,arch=arm64' \
  -only-testing:ConductorTests/CDRVersionTests/testNumericComponentComparison
```

Omitting `arch=arm64` triggers a harmless multiple-destination warning.
`-quiet` swallows too much; when hunting failures, redirect full output to a
file and grep for `Test case`/`error:`.

`CDRCodeSignatureTests` run against the built Conductor.app itself and expect
Team `F252L9GUBW` — they fail under a different signing team.

## Integration tests & the e2e harness

`CDRUpdateOperationIntegrationTests` drive the real engine against a local
`python3 -m http.server` using artifacts from `TestHarness/build-testee.sh`
(run it first; tests skip when `TestHarness/serve/` is absent). The script
signs ConductorTestee v1.0/v1.1 with the Developer ID identity and emits
adversarial artifacts (replay of older signed build, ad-hoc signature,
downgrade/retraction manifest, wrong bundle ID).

Until the artifacts are notarized (`build-testee.sh --notarize`, needs a
notarytool keychain profile, default `AC_NOTARY`), the positive-path test
asserts a clean refusal at the notarization gate rather than the full swap —
this is expected, not a failure; it auto-upgrades to asserting the swap when
stapled artifacts are present.

Manual GUI run: serve `TestHarness/serve/`, `ditto` v1.0 into /Applications,
launch with arguments `--dev-mode com.ranvel.conductor-testee`.
