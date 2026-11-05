# CND-4 recon — Settings v2 and per-app overrides

Cici, 2026-11-05. Fable Protocol: recon, solutioning and implementation ran
as one pass.

## Outcome

Implemented: storage, resolution and UI for every v2 user policy. Nothing
acts on the values yet except the detail pane's "N … hidden · Show" line,
which now follows the selected app's resolved shown categories. Holding,
major stops and per-app deferral are CND-5; the network gate is CND-7.

## Findings (Recon 1)

- The M3 Settings window was a single fixed 440×480 form, not a tab view.
  It is now a single **scrolling** form, 640pt wide, height resizable.
- Bindings before: login item → `SMAppService` (not defaults); visibility →
  `CDRShowMenuBarItem` / `CDRShowDockIcon`; deferral → `CDRSoakDuration`
  token; cadence → `CDRScanCadence` token; ignores → `CDRIgnoredBundleIDs`
  via `onRowAction`. All five keep their keys, tokens and behavior.
- The deferral popup mapped **menu index → enum raw value**. A 3-day item
  between "1 day" and "1 week" would have shifted `1w`'s index, so the new
  control maps through `CDRSoakDurationChoices()` instead.
- `CDRIgnoreList` (a sorted array of bundle IDs in NSUserDefaults) is the
  existing per-app store pattern; overrides follow it.

## Forks resolved

| Fork | Chosen | Why |
|---|---|---|
| Recon 1: tab view or one scroll | one scrolling form | matches the PNG |
| Recon 2: where overrides persist | (a) NSUserDefaults, `CDRAppPolicyOverrides` = `{bundleID: {…}}` | preferences are not update memory; the state store drops records after 90 days |
| Recon 3: is Fixed off for "Normal user" | no — only Security is hidden | the PNG's grid shows Fixed checked under Normal user, and the Main window PNG says "2 security fixes hidden" |
| Recon 3: editing a checkbox after a preset | scheme becomes `custom`, all three radios deselected | as recommended |
| Recon 3: Developer | Everything + `exposesDeveloperDetail` | read by the row model now, used by CND-7 |
| Recon 4: 3-day step | `CDRSoakDurationThreeDays` **appended** (raw value 3), token `3d` | `Off`/`OneDay`/`OneWeek` keep raw values 0/1/2 and tokens `off`/`1d`/`1w` |
| Recon 6: Retracted | forced into `shownTypes` and `holdTypes` on every construction path | reading defaults, the mutable twin, copying, the override parser and the resolver all pass through one function; a `defaults write` cannot remove it |
| Per-app shown override vs the scheme | the override replaces the category set but keeps the user's scheme | Developer detail is a property of the user, not of one app |
| OVERRIDDEN tag | shown when that section's override is set, even if the value equals Settings | the section no longer follows Settings, which is what the tag says |
| Per-app deferral choices | Follow Settings / Never / 1 week | as the PNG draws it. A stored 1-day or 3-day override (only reachable by `defaults write`) is honored and shown as "This app: 3 days" with no segment selected |
| How rows learn the preferences | `CDRAppRowContext.preferences`, resolved by `CDRUpdateController` per app | the detail pane still renders only from the row model |

## Things the ticket and the PNG left open

- **Network overrides.** The ticket says `CDRAppPolicyOverride` holds an
  optional "for each field". The popover in the PNG offers four policies and
  no network control, so the override has those four fields only. Adding
  network fields with no way to set them would be dead storage.
- **Where the M3 controls go.** The PNG shows only the four new groups. The
  login item, visibility and cadence are in a fifth group, "Conductor", and
  the ignore list in a sixth, "Ignored apps", below them.
- **Popover width.** Four badge checkboxes across did not fit the PNG's
  width with glyph badges, so the popover grid uses label-only badges (as
  the PNG's popover does) and the popover is 400pt wide.

## What changed

New:
- `Conductor/Engine/CDRUpdatePreferences.{h,m}` — `CDRInterestScheme`,
  `CDRUpdatePreferences` (+ mutable twin), `CDRAppPolicyOverride`, the
  override store functions, `CDRPolicyResolver`, the summary and echo
  wording. Pure apart from the defaults round-trip.
- `Conductor/UI/CDRCategoryGridView.{h,m}` — the badge-checkbox grid.
- `Conductor/UI/CDROverridePopoverController.{h,m}` — the per-app popover.

Changed:
- `CDRUpdatePolicy` — the 3-day step, `CDRSoakDurationChoices()`,
  `CDRSoakDurationDisplayName()`.
- `CDRReleaseNote` — type set ↔ keys, display list.
- `CDRSettingsWindowController` — rebuilt as the scrolling form; adds
  `onPreferencesChanged` and `showSection:`.
- `CDRAppRowModel` — `shownTypes`, `exposesDeveloperDetail`.
- `CDRDetailViewController` — hidden categories read `row.shownTypes`.
- `CDRMainWindowController` — owns the popover; the header's override
  button is enabled.
- `CDRUpdateController` — resolves preferences per app;
  `-preferencesDidChange`.
- `CDRViews` — compact (label-only) badges.

Tests: `CDRUpdatePreferencesTests` (new), `CDRSettingsTests` (new, drives
the real controls against a throwaway defaults suite),
`CDRMainWindowTests`.

## Left for CND-5

- The comment on `CDRSoakDuration` still says "one value for all managed
  apps, no per-app overrides"; the ticket assigns that fix, and
  `docs/deferral.md`, to CND-5.
- `CDRUpdateController` still passes the **global** deferral token to the
  policy. Per-app deferral takes effect when CND-5 threads the resolved
  preferences through.

## How it was checked

- 228 tests pass (`-only-testing:ConductorTests`), integration included.
- Settings and the popover were rendered in light and dark to
  `$TMPDIR/CDRRenders/` and compared with
  `ref-assets/Settings + per-app overrides` by eye.

## What I could not check

- The popover opening from the real header button, and its placement —
  r's own debug Conductor was running, so I did not launch a second one.
- The login item checkbox reflects the machine's real `SMAppService`
  status; it is not exercised by tests.
