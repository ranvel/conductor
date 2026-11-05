# CND-3 recon — two-pane main window

Cici, 2026-11-05. Fable Protocol: recon, solutioning and implementation ran
as one pass.

## Outcome

Implemented. `CDRStatusWindowController` is gone; the main window is a
two-pane `NSSplitViewController` (apps left, the selected app's update and
notes right) built from new files under `Conductor/UI/`. It renders only
from `CDRAppRowModel`; the menu bar and Settings still read the same models
and the same `stateLine` strings, so they are unchanged.

Not verified by me: the live window with its title bar (see "What I could
not check").

## Findings (Recon 1)

- The old window was a stock four-column `NSTableView` plus three buttons
  and a progress row. There were no custom views, no split view, no sheets
  and no named colors anywhere in the app.
- `AppDelegate` is the only `CDRUpdatePresenting` conformer; the window was
  never one. That seam survives untouched.
- The activity log already lived in its own window (`CDRLogWindowController`,
  ⌘L). Fork (a): it stays there.
- What was scaffolding and is deleted: `CDRStatusWindowController.{h,m}`.
  What carried over into the new list: the context-menu action table,
  selection that survives a reload (by bundle ID), the red dev-mode banner,
  the aggregate progress line.

## Forks resolved

| Fork | Chosen | Why |
|---|---|---|
| Recon 1: activity log | (a) separate window | already exists; nothing to move |
| Recon 3: layout | (a) `NSSplitViewController` + `NSTableView` left, scrolling stack right | divider, autosave and min widths for free |
| Retraction State A row state | new `CDRAppRowStateRetracted` (was `UpToDate` with a retraction line) | the section is then a pure function of the state; no existing test asserted the old state |
| Rows Conductor can't vouch for (not checked, check failed, ignored) | a fourth section, **NOT CHECKED**, shown only when non-empty | the PNG has three sections and doesn't draw these states; filing a failed check under "UP TO DATE" would be a false statement |
| Stopped-at-major section | NEEDS YOU, as CND-5 says | **differs from the PNG**, which shows Swift Unxip under UPDATES and "3 need you"; with the ticket's rule the same rows read "4 need you". One line in `CDRAppRowSectionForState` if r prefers the PNG |
| "Deferred · 2 days left" needs a clock | `-shortStateLineAsOf:` takes `now` | the factory keeps its "no I/O, no clock" contract |
| New row inputs (developer name now; preferences and network posture later) | optional `CDRAppRowContext` on a new factory variant | the old seven-argument factory still exists and every existing test calls it unchanged |
| Colors | 31 named colorsets under `Assets.xcassets/Palette`, read through `CDRPalette` | hex values sampled from the PNGs, light and dark |
| Default selection | first row of the top-most section that isn't UP TO DATE; nothing when everything is current | so "Everything's up to date" can show; the user's own choice then sticks until that app goes away |
| "Got it" on a retraction | new `CDRAppRowActionAcknowledge` → a passive re-check | the decision already cleared the notified memory, so the re-check lands on "up to date". In-memory only; CND-6 adds persistence |
| Developer name in the header | `CDRBundleInspector`, the signing certificate's Organization | display only; `CDRCodeSignature` untouched |

## What is placeholder until later tickets

- **NETWORK row** — drawn, says "Unknown · Conductor hasn't inspected this
  app's network access." (CND-7).
- **Held / StoppedAtMajor / Inspecting / NeedsNetworkApproval** — in the
  enum, sectioned, worded and drawn; nothing produces them yet (CND-5,
  CND-7). The fixtures in `ConductorTests/CDRRowFixtures.m` build them.
- **Per-app override button** — present, disabled until `onShowOverrides`
  is set (CND-4).
- **"Always allow for this app"** — present, disabled (CND-5).
- **Hidden categories** — `shownTypes` on the detail controller defaults to
  everything; CND-4 feeds the user's choice.
- **Deferred pane's "Update now"** sends the existing per-app Check Now,
  which still raises the old confirmation alert (CND-5 makes the pane click
  the consent). "Keep waiting" does nothing, by design.
- **Deferred pane copy** — the PNG says "You wait 3 days…"; the row model
  doesn't know the setting yet, so it says "Your update settings hold new
  builds for a while…" (CND-5).
- **Retraction pane copy** — the PNG gives the advertised and pulled dates;
  neither is stored yet, so it says "1.2 was advertised, then pulled."

## What changed

New, `Conductor/UI/`:
- `CDRPalette` — named colors; ink / fill / glyph per note type.
- `CDRViews` — `CDRSurfaceView`, `CDRHairlineView`, `CDRButton`,
  `CDRBadgeView`, `CDRCategoryDotsView`, `CDRProgressBarView`, label and
  symbol helpers. All draw in `-drawRect:` from dynamic colors.
- `CDRAppListViewController` — search, sectioned table, context menu.
- `CDRDetailViewController` — header, NETWORK row, grouped notes, skipped
  versions, the state panes.
- `CDRMainWindowController` — window, toolbar, split view, selection.
- `CDRWindowCopy` — pure wording and the row → primary-button mapping.

New elsewhere: `Conductor/Engine/CDRBundleInspector`,
`Conductor/CDRAppRowModel_Private.h`, `Conductor/Assets.xcassets/Palette/`.

Changed: `CDRAppRowModel` (five new states, section, short state line,
dots, releases, context), `CDRUpdateController` (developer name,
`lastCheckDate`, acknowledge), `AppDelegate` (new window, Window ▸
Conductor ⌘0, "Scan again"), `CDRReleaseNote` (noun and count phrases).

Deleted: `CDRStatusWindowController.{h,m}`.

Tests: `CDRMainWindowTests` (new), `CDRRowFixtures` (new),
`CDRAppRowModelTests`, `CDRReleaseNoteTests`, `CDRCodeSignatureTests`.

## How it was checked

- 200 tests pass (`-only-testing:ConductorTests`), integration included,
  against the notarized harness.
- `CDRMainWindowTests` draws every pane in light and dark to
  `$TMPDIR/CDRRenders/*.png` (34 images). I compared them with
  `ref-assets/` by eye: layout, badge order, dot colors, the hidden-category
  line, the collapsed and expanded 1.3 row, and the six edge states match.
  The pixel assertions pin the pane backgrounds in both appearances.

## What I could not check

- **The title bar** ("Conductor · 7 updates · 3 need you", "Checked 4 min
  ago", Check now, the settings glyph). The render captures the content
  view only, and r's own debug Conductor was running throughout, so I did
  not launch a second instance beside it.
- **Divider position persisting across launches**, for the same reason.
- App icons: fixtures use one stand-in icon; real rows use each app's own.
