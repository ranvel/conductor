# CND-7 recon — network gate

Cici, 2026-11-05. Fable Protocol: recon, solutioning and implementation ran
as one pass. Signature and filesystem investigation went through the
`recon` agent; its scratch files are under the session scratchpad
(`…/scratchpad/recon7/`).

## Outcome

Implemented. The update operation has an Inspect phase after Verify; the
controller looks ahead at builds that could gain network access, parks them
for approval, and drives the two network sheets; the NETWORK row shows real
data. Verified end to end against five notarized testee builds.

**The verification path is unchanged.** `git diff 13b625e` is empty for
`CDRCodeSignature`, `CDRAtomicSwapper`, `CDRNotarizationCheck`,
`CDRQuarantine`, `CDRArtifactStager`, `CDRArtifactDownloader`,
`CDRDevModeSession`, `CDRManifestFetcher` and the privileged helper.
`kCDRValidationFlags` is untouched. In `CDRUpdateOperation.m` exactly two
existing lines changed: the last line of `stepVerify` now calls
`stepInspect:` instead of `stepQuitCheck:`, and the retraction error gained
a userInfo key.

## Findings

### Recon 1 — the ticket's flag assumption was wrong

`kSecCodeInfoEntitlementsDict` does **not** need `kSecCSRequirementInformation`.
It comes back from `SecCodeCopySigningInformation` with any flags, including
the `kSecCSSigningInformation` call `CDRCodeSignature` already makes
(`SecCode.h` marks the key "generic"). Measured on this Mac (macOS 27.2):

| Bundle | Entitlements dict | sandbox / client / server |
|---|---|---|
| Safari | present | true / true / absent |
| Stickies, TextEdit | present | true / absent / absent |
| LocalSend | present | true / true / true |
| ConductorTestee (old, unsandboxed) | **absent** | — |
| Conductor.app (debug) | present, 3 unrelated keys | absent |
| ad-hoc `echo` | absent | — |
| unsigned bundle | absent, and no Identifier | — |

So: a missing dict on a signed bundle means "no entitlements" (→ not
sandboxed → unrestricted); a missing **Identifier** means "not signed"
(→ Unknown). Values are real booleans. Non-sandboxed apps often carry
`network.*` keys under the hardened runtime; they mean nothing outside the
sandbox.

### Recon 2 — Internet Access Policy

**I could not read Objective Development's published format.** Their
developer page is a JavaScript-rendered help site; two fetch attempts
returned only the shell. The parser is written against **21 real policy
files in /Applications on this Mac** (BBEdit, Postico, Suspicious Package,
Little Snitch, Dato, …), which agree with each other:

- Top level: `ApplicationDescription`, `Connections`, `DeveloperName`,
  `Website`, `Services`.
- Connection: `Host` (string; may be comma-separated, may use `*`),
  `Purpose`, `DenyConsequences`, `NetworkProtocol`, `IsIncoming`, `Port`
  (a string, e.g. `"80, 443"`), `Relevance`.
- Text is either literal or a key into `<lang>.lproj/InternetAccessPolicy.strings`.
- Layouts seen: `Contents/Resources/InternetAccessPolicy.plist` (binary or
  XML), `…/Base.lproj/InternetAccessPolicy.plist` (Little Snitch), and
  `…/InternetAccessPolicy.json` (Dato).

Honored: `Connections` → (host, purpose) rows, all three layouts, the
`.strings` lookup. Read but not shown: `Services`, `DenyConsequences`,
`Relevance`, the top-level metadata. If the published spec says something
these 21 files don't show, the parser will need a look.

The policy file is listed in each bundle's `_CodeSignature/CodeResources`,
and `kCDRValidationFlags` does not skip resource validation — so for a
staged build it is read from under the seal Verify just checked.

## Forks resolved

| Fork | Chosen | Why |
|---|---|---|
| Recon 1: where the reader lives | `CDRBundleInspector` (the display-only sibling from CND-3), not `CDRCodeSignature` | `CDRCodeSignature` stays the security perimeter and nothing else |
| Recon 3: where the pause lives | (a) a new `Inspecting` phase after Verify; the operation parks until its delegate replies | one operation owns staging and cleanup |
| Quit / relaunch with an approval parked | discarded; nothing persists | as recommended |
| Recon 4: when inspection starts | (a) automatically — **but only for apps whose installed build has no (or unreadable) network access** | a build that already has access can't "gain" it, so nothing is downloaded ahead of time for most apps. Narrower than (a) as written |
| Does a look-ahead ever install | no: it always stops at the approval step, even when the gate says "don't ask" | nothing installs without a click, as before |
| Recon 5: unreadable entitlements | Unknown, never "none"; errs toward asking, never claims good news | when in doubt, ask |
| "Already has access" + more access | not asked (Client → Both, Client → unsandboxed) | the ticket's rule is the crossing from no access to access |
| Dropping the sandbox | counts as gaining access, asked | sandboxed-none → unrestricted is the largest possible gain |
| A policy with no usable rows | treated as no policy | it explains nothing |
| Recon 6: "Skip this version" | new `skippedVersion` on `CDRAppUpdateState`; new outcome `Skipped`; forgotten when a different version is advertised or the app is checked by hand | no per-version skip memory existed |
| Where a skipped row sits | UPDATES, as "0.5 skipped" | it is newer than what's installed; never "up to date" |
| A failed look-ahead | logged, no notification, update still offered, not retried for that version | the user never asked for an install |
| Long park | manifest re-fetched before continuing if the last check was over 5 minutes ago; a retraction aborts; an unreachable manifest aborts too | retraction.md's last-moment re-check, repeated |
| Quitting mid-inspect | a look-ahead never delays quitting; staging is removed in `applicationWillTerminate`, and again at next launch as before | "no staging behind" |

## What changed

New:
- `Conductor/Engine/CDRNetworkInspection.{h,m}` — `CDRNetworkPosture`,
  `CDRNetworkChange`, `CDRNetworkInspection`, `CDRNetworkGate` (pure).
- `Conductor/Engine/CDRInternetAccessPolicy.{h,m}` — the parser.

Changed:
- `CDRBundleInspector` — `entitlementsForBundleAtURL:teamID:`,
  `networkPostureForBundleAtURL:`.
- `CDRUpdateOperation` — `CDRUpdatePhaseInspecting`, `stepInspect:`,
  `parkedForApproval`, `cancelParkedApproval`, `stepRecheckAfterPark:`,
  the optional delegate method `updateOperation:didInspect:reply:`. A
  delegate that doesn't implement it gets the old pipeline exactly.
- `CDRErrors` — `CDRErrorApprovalDeclined` (505), `CDRErrorIsRetractionKey`.
- `CDRAppUpdateState`, `CDRUpdateStateStore`, `CDRUpdatePolicy` —
  `skippedVersion`, `noteSkippedVersion:…`, outcome `Skipped`.
- `CDRUpdateController` — installed-posture cache, look-ahead, parking,
  approve / skip / dismiss, supersede, quiet look-ahead failures,
  `discardParkedApprovals`.
- `CDRAppRowModel` — Inspecting / NeedsNetworkApproval / Skipped rows; the
  NETWORK row's title, detail, tone, policy rows, developer lines.
- `CDRDetailViewController` — the real NETWORK row (expandable), skipped
  pane, inspecting steps by phase.
- `AppDelegate` — staging removed at terminate. `CDRSettingsWindowController`
  — the bandwidth sentence under the network toggle.
- `TestHarness/build-testee.sh` — sandboxed 1.0 / 1.1; 1.2 (+client, with
  policy); 1.3 (+client, no policy); 0.9 (unsandboxed);
  `manifest-1.2.json`, `manifest-1.3.json`.
- `docs/replace-flow.md` §3a, `docs/spec.md` §5.1.

## How it was checked

320 tests pass (`-only-testing:ConductorTests`), none skipped, against
artifacts built with `build-testee.sh --notarize` (all five accepted).

| DAT line | Covered by |
|---|---|
| NETWORK row: none / with policy / no policy / non-sandboxed has access | `testNetworkRowForTheThreeInstalledStates`, `testNetworkRowDrawsTheRowModelAndExpandsToThePolicy`, renders |
| +client with policy, exemption on: installs without a sheet, row shows the change | `testWithTheExemptionOnAPolicyBuildInstalls…`; real build in `testBuildThatGainsAccessWithAPolicy…` |
| Same, exemption off: sheet with diff + policy, Approve default; Approve installs, Skip discards and marks skipped | `testWithTheExemptionOffAPolicyIsShown…`, `testABuildThatGainsAccessWithoutAPolicy…SkipIsRemembered`, CND-6 sheet tests |
| +client, no policy: "no policy" sheet, Skip default, amber strip | controller test above + `testTheSafeChoiceIsAlwaysTheDefaultButton`; real build in `testBuildThatGainsAccessWithoutAPolicyIsDiscardedWhenDeclined` |
| Non-sandboxed → sandboxed-none never asks, row celebrates | `testBuildThatDropsNetworkAccess…` (real 0.9 → 1.1), `testABuildThatDropsAccessNeverAsks` |
| Step list advances; quitting mid-inspect leaves /Applications untouched, no staging | step index by phase and the Inspecting render; `testParkedApprovalHoldsTheVerifiedBuildAndCancellingDiscardsIt`. **The quit path itself (`applicationWillTerminate`) is not covered by a test** |
| Inspect never runs on a build that failed Verify | `testInspectNeverRunsOnABuildThatFailedVerify` (ad-hoc), `…OnAReplayedOlderBuild` |
| `CDRCodeSignature` unchanged, `kCDRValidationFlags` untouched | the `git diff` above |

## What I could not check

- **The planned manual GUI pass** (testee in /Applications, dev mode,
  update through the gate). r's own debug Conductor (launched 09:15) was
  running the whole session; I did not start a second instance beside it
  or put a test app in /Applications under it.
- **A real look-ahead from the controller.** The operation is tested end to
  end with real builds, and the controller's parking / approve / skip logic
  with a stand-in operation — but not the two joined, because the
  controller scans the real /Applications.
- The network sheet dropping from the live window, and quit cleanup.

## Things r should know

- With the gate on (the default), Conductor now **downloads an available
  update in the background** for any managed app whose installed build is
  sandboxed with no network entitlement. Settings says so under the toggle.
- The unit tests are hosted in Conductor.app. Each run launches it, which
  removes `/Applications/.conductor-staging` at launch (as before) and now
  also at quit.
- `CLAUDE.md`'s phase list (Fetch → … → Verify → AwaitQuit → …) no longer
  mentions Inspect. I left the file alone, as agreed.
- To look at the two disk images I mounted them briefly under `/tmp` and
  detached them.
