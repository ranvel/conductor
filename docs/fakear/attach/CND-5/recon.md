# CND-5 recon — holds, major-version stops, per-app deferral

Cici, 2026-11-05. Fable Protocol: recon, solutioning and implementation ran
as one pass.

## Outcome

Implemented. `CDRUpdatePolicy` now takes the app's resolved
`CDRUpdatePreferences` and can answer `Held` or `StoppedAtMajor`.
`CDRUpdateController` resolves preferences per app, re-decides pending
updates when a preference changes, and handles the two pane actions. No
verification, download or swap code changed.

## Findings (Recon 1)

- **Nothing auto-installs, and nothing did.** `installApp:` is reached only
  from a row's Install action, the "update available" notification's
  Install button, and the deferred-offer dialog's "Install Anyway". So
  "held — never auto-installed" does not mean stopping an automatic
  install; it means a held update must not be reachable from a
  notification banner and must be told apart in the list. That is what was
  built: a held or stopped update gets the passive "is waiting for you"
  notice, which has **no Install action**.
- The decision function ended in plain `Available` on four paths (urgency,
  already notified, deferral off, matured). All four now go through one
  block, `surfaced(…)`, which applies the gates.
- The state-table tests call the policy through one helper per file (four
  files). Those helpers were updated; no existing row was rewritten.

## Forks resolved

| Fork | Chosen | Why |
|---|---|---|
| Recon 2: new outcomes or flags on `Available` | new outcomes `Held`, `StoppedAtMajor` | every state-table row still maps to exactly one outcome |
| Recon 3: signature | `preferences:` replaces `soakDuration:`; tests updated, no shim | as recommended |
| Recon 4: major comparison | `+[CDRVersion majorComponentOf:]`, `+isMajorUpgradeFrom:to:` | leading component grew; non-numeric on either side is never major |
| Recon 7: Held + StoppedAtMajor | outcome `StoppedAtMajor`, with `heldTypes` still set | major stop wins the state line; the hold is not lost |
| What a hold looks at | the advertised release **and** every skipped release the user would also take | a 1.2 → 1.4 update includes 1.3's removal |
| Existing state-table rows vs default hold categories | the old helpers use preferences with no hold categories | those rows are statements about deferral and retraction; new rows use shipped defaults |
| Preference changes | re-decide pending updates immediately, from the manifest in hand, with no fetch and no notification | "releases that hold on the next check" becomes "releases it now"; retraction notices are skipped so an unread one isn't erased |
| "Update now" on the deferred pane | a new action, `InstallDeferred`: consent → mark notified → decide again → install only if plainly Available | the ticket's "hidden is hidden; gates apply to surfaced updates" — consent surfaces it, then the gates apply |
| "Always allow for this app" | new action `AlwaysAllowMajor`: writes `stop_at_major: false` for the app, then re-decides | Settings itself is untouched |
| Held / stopped notification | new `notifyUpdateNeedsAttention…`, posted without an Install action | a held update is installed from the window |

## Differences from the ticket's wording

- **"Both gates must be passed to install."** When an update is both held
  and stopped at a major version, the stopped pane's "Install 1.0" starts
  the install in this ticket. The second confirmation is the held sheet,
  which is CND-6; there I route Install on any row with held categories
  through that sheet, so the stopped pane's button will open it.
- **Section placement.** As planned, StoppedAtMajor rows sit under NEEDS
  YOU (the ticket), not UPDATES (the PNG).
- **The old break-through dialog still exists** for "Check Now" from a
  row's context menu or the menu bar on a deferred app. The pane's
  "Update now" is the dialog-free route.

## What changed

- `Conductor/Engine/CDRUpdatePolicy.{h,m}` — `preferences:` parameter; the
  `surfaced` gate block; outcomes `Held`, `StoppedAtMajor`; decision gains
  `heldTypes`, `stoppedAtMajor`; `CDRUpdateGateReasonCopy`; the stale
  "no per-app overrides" comments rewritten.
- `Conductor/Engine/CDRVersion.{h,m}` — the two major-version helpers.
- `Conductor/CDRUpdateController.m` — `evaluateManifest:…notify:`,
  resolved preferences, `preferencesDidChange` re-decides, the two new
  actions, quiet handling when nothing was fetched.
- `Conductor/CDRAppRowModel.{h,m}` — Held and StoppedAtMajor rows,
  `InstallDeferred` / `AlwaysAllowMajor` actions, `deferralDurationName`.
- `Conductor/CDRUpdatePresenting.h`, `AppDelegate.m` —
  `notifyUpdateNeedsAttention…`.
- `Conductor/UI/CDRDetailViewController.m`,
  `CDRAppListViewController.m` — pane buttons and context menu wired; the
  deferred pane now says "You wait 3 days before new builds show up."
- `docs/deferral.md`, `docs/roadmap.md`, `docs/spec.md` §8.

Tests: `CDRUpdatePolicyTests` (+17 rows: H1–H9, M1–M5, HM, per-app
deferral, held-then-retracted), `CDRVersionTests` (+3),
`CDRAppRowModelTests` (+4), `CDRNotificationGateTests` (+1),
`CDRMainWindowTests`, and new `CDRUpdateControllerPolicyTests` (8), which
drives a real `CDRUpdateController` with a fixture scanner and a recording
presenter.

## How it was checked

260 tests pass (`-only-testing:ConductorTests`), integration included.
Each DAT line has a test:

| DAT line | Test |
|---|---|
| Removal → Held under NEEDS YOU, no install until clicked | `testAnUpdateWithARemovalIsHeld…`, `testHeldRowNeedsYou…` |
| Removing Removed from holdTypes releases it (global or per app) | `testRemovingTheHoldCategoryReleasesTheHold…` |
| 0.9 → 1.0 stops; "Always allow" writes an override and it proceeds | `testAlwaysAllowForThisApp…` |
| 1.9 → 1.10 is not a major stop | `testM2…`, `testAMinorBumpIsNotStopped` |
| Per-app 1 week while Settings is Off; Check now breaks through | `testAPerAppDeferralHoldsOneApp…` |
| Urgency bypasses deferral but lands in Held | `testH4…`, `testUrgencyBypassesDeferralButStillLandsInHeld` |
| Held then retracted is loud | `testAHeldUpdateThatIsLaterRetractedIsLoud` |
| New state-table rows; existing rows unchanged | the 29 pre-existing policy tests pass untouched |

## What I could not check

The live window: clicking the pane buttons in a running app. r's own debug
Conductor was running, so I did not launch a second instance.
