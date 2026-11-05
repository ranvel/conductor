# CND-6 recon — interrupt sheets

Cici, 2026-11-05. Fable Protocol: recon, solutioning and implementation ran
as one pass.

## Outcome

Implemented. One sheet component (`CDRInterruptSheetController`) draws all
four variants from a pure `CDRInterruptSheetModel`. Held and Retraction are
wired; the two network variants render from test data and have their
presenter entry point, waiting for CND-7's inputs.

## Findings (Recon 1): every `present*` / `notify*` before this ticket

`AppDelegate` is the only `CDRUpdatePresenting` conformer. The window and
menu bar do not conform.

| Call | From | Was |
|---|---|---|
| `presentQuitDecision…` | operation asks to quit the app | `NSAlert runModal` — unchanged |
| `presentDeferredOffer…` | per-app Check Now on a deferred update | `NSAlert` — unchanged |
| `presentRetractionNotice:vendorURL:` | install-time re-check found a retraction | `NSAlert` — **replaced** |
| `presentRelaunchOffer…` | after a quit-and-update | `NSAlert` — unchanged |
| `notifyUpdateAvailable…` | check | notification — unchanged |
| `notifyUpdateNeedsAttention…` | check (CND-5) | notification — unchanged |
| `notifyRetractedPending…` | check, State A | notification — still used, see below |
| `notifyRetractedInstalled…` | check, State B | notification — unchanged |
| `notifyInstallCompleted…` / `…Failed…` | operation finished | notification — unchanged |

The rule "modal only inside a user-started flow" held everywhere and still
does.

## Forks resolved

| Fork | Chosen | Why |
|---|---|---|
| Recon 1: a retraction found by a check | **narrower than (a)**: the sheet only when the user started the check *and* the window is key; a scheduled check is always notification + banner | r's standing rule is no modals from passive checks. (a) as written would drop a sheet on a key window during a scheduled check. Approved in the plan |
| What counts as user-started | the title-bar / menu-bar "Check now", the up-to-date pane's button, "Scan again", and a per-app Check Now | `checkAllUserStarted` is new; the scheduler still calls `checkAllPassive`. Neither breaks through deferrals — only the per-app check does |
| Persistent banner | a small store of unacknowledged notices in NSUserDefaults (`CDRRetractionNotices`), read by the row model through its context | the policy's "loud once, then cleared" memory and its state-table rows stay exactly as they are; the banner is presentation state |
| When a notice is dropped | on "Got it" / the sheet's OK; or when it is moot (a newer version is advertised, or State B takes over) | a notice about a pulled build means nothing once something newer is on offer |
| Recon 2: component | one `NSWindowController` per presentation, value model, buttons as `{title, action}` | as recommended |
| Recon 3: Held | Install on any row with held categories opens the sheet — Held rows, and StoppedAtMajor rows that also carry a hold | this is the second confirmation CND-5 left open |
| "Change in Settings" | dismisses the sheet, opens Settings scrolled to the hold group (`showSection:` from CND-4) | — |
| Recon 5: network entry point | `presentNetworkApprovalForAppNamed:…diffLines:policyRows:completion:`, implemented (not stubbed) | the sheet already draws those sections; CND-7 only has to call it |

## Things worth knowing

- **Escape on the retraction sheet.** It has one button, so Escape (and
  Return) both mean OK.
- **Sheets need a visible window.** `presentInterruptSheet:` refuses when
  the window is off screen or already has a sheet, and reports "dismiss".
  Held and network presentation bring the window forward first (the user
  pressed Install); retraction does not — it falls back to the notice.
- **Several retractions in one user-started check:** the first gets the
  sheet, the rest fall back to notifications. Every one keeps its banner.
- **The old break-through `NSAlert`** and the quit and relaunch alerts are
  untouched, as the ticket says.

## What changed

New:
- `Conductor/UI/CDRInterruptSheetModel.{h,m}` — the four variants, the
  default-button rule, response → action; `CDRNoteGroupsOfTypes`.
- `Conductor/UI/CDRInterruptSheetController.{h,m}` — the component.
- `Conductor/CDRRetractionNotices.{h,m}` — unacknowledged notices.

Changed:
- `CDRUpdatePresenting.h` — `presentRetractionForAppNamed:…completion:`
  (replaces `presentRetractionNotice:vendorURL:`),
  `presentHeldUpdateForAppNamed:…`, `presentNetworkApprovalForAppNamed:…`.
- `AppDelegate.m` — implements the three; "Check now" is user-started.
- `CDRUpdateController.{h,m}` — `checkAllUserStarted`; Install on a held
  update asks for the sheet; retraction routing; notices recorded, cleared.
- `CDRAppRowModel.{h,m}` — a pending notice keeps the row Retracted;
  `retractionAdvertisedDate`, `retractionPulledDate`.
- `CDRMainWindowController.{h,m}` — `presentInterruptSheet:completion:`.
- `CDRDetailViewController.m` — the retraction pane gives the dates.
- `docs/retraction.md` — how State A reaches the user.

Tests: `CDRInterruptSheetTests` (new, 10), `CDRUpdateControllerPolicyTests`
(+8, now driving real checks through a fixture fetcher),
`CDRAppRowModelTests` (+2), `CDRMainWindowTests` (+2).

## How it was checked

- 282 tests pass (`-only-testing:ConductorTests`), integration included.
- All four sheets were rendered in light and dark to `$TMPDIR/CDRRenders/`
  and compared with `ref-assets/Interrupt sheets` by eye.

| DAT line | Covered by |
|---|---|
| Install on a Held row opens the held sheet, notes badged, Install default | `testInstallOnAHeldRowOpensTheHeldSheet…`, `testTheSafeChoiceIsAlwaysTheDefaultButton`, render |
| Not now leaves it Held; Install proceeds and marks notified | `testInstallOnAHeldRow…`, `testInstallFromTheHeldSheetProceeds…` |
| "Change in Settings" opens Settings at the hold group | `showSection:` is tested in CND-4; the link → Settings hop in `AppDelegate` is **not** covered by a test |
| Retraction while the window is key → sheet; while hidden → notification + banner | controller routing and the persistent banner are tested; the "is the window key" branch in `AppDelegate` is **not** |
| Light and dark; Escape = secondary, Return = default | renders; `testEveryVariantLaysOutInBothAppearances` (key equivalents) |
| Network variants render from test data | `testEveryVariantLaysOut…`, `testOptionalSectionsAppear…` |

## What I could not check

A sheet actually dropping from the live window, and the two `AppDelegate`
branches marked above. r's own debug Conductor was running, so I did not
launch a second instance.
