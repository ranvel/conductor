---
key: CND-4
summary: Settings v2 — interest scheme, shown categories, manual-install triggers, major-version stop, network gate; per-app overrides
status: DAT
resolution:
priority: High
fixVersion:
created: 2026-11-05
updated: 2026-11-05
session:
tags: [v2, settings, preferences, per-app]
related: [CND-3, CND-5, CND-7]
---

# CND-4 — Settings v2 and per-app overrides

## Context
	Read `docs/conductor-v2.md` first. Spec for this ticket:
	`ref-assets/Settings + per-app overrides · Light@2x.png` + `Dark@2x.png`.

	This ticket is the *storage and UI* for every v2 user policy. The
	policy *behavior* (holding, stopping at majors, per-app deferral) is
	CND-5; the network behavior is CND-7. Build the settings so those
	tickets only read values.

	Global Settings window, four groups per the PNG:
	- Updates: Defer new updates (Off / 1 day / 3 days / 1 week — note the
	  new 3-day step); Stop at major versions (toggle, default off).
	- What you see: Interest scheme (Normal user / Everything / Developer)
	  — a preset that seeds Shown categories; Shown categories as a grid of
	  checkboxes using the real badge views (Retracted is always on and
	  rendered disabled-checked).
	- Install manually when an update includes… — the same grid; defaults
	  Notice, Removed, Retracted on.
	- Network: Require approval when an app gains internet access (default
	  on); "…unless it ships an Internet Access Policy" (default on, nested,
	  disabled when the parent is off).

	Per-app overrides: a popover from the detail header's override button.
	Every control is a tri-state "Follow Settings | <override values>",
	with the current global value echoed beneath ("Settings: 3 days"), an
	OVERRIDDEN tag on any section that differs, a one-line summary of the
	diff ("Security shown and Fixed hidden for muwav only"), and Reset to
	Settings. Shown categories override is "Follow scheme | Custom" + grid.

	The existing Settings window (`CDRSettingsWindowController`: login
	item, visibility, soak, cadence, ignores) stays; these groups join it.
	Keep existing defaults keys stable — `CDRSoakDurationDefaultsKey`'s
	token format is a durable contract (its "no per-app overrides" comment
	is now wrong and gets updated in CND-5).

## Recon
	Cici — where an answer forks, give lettered options with a recommendation.
	1. Map `CDRSettingsWindowController` and how each existing control binds
	   to defaults; map `CDRIgnoreList` as the existing per-app store
	   pattern. Confirm whether the window is a tab view or a single
	   scroll; recommend a single scrolling form per the PNG.
	2. Design the policy model. Recommend one immutable value object,
	   `CDRUpdatePreferences` (soak, stopAtMajor, interestScheme,
	   shownTypes as a type-set, holdTypes as a type-set,
	   requireNetworkApproval, policyExemptsApproval), with a defaults
	   round-trip in one place, and a `CDRAppPolicyOverride` holding
	   optionals for each field. A `CDRPolicyResolver` returns the
	   effective `CDRUpdatePreferences` for a bundle ID (override ∘ global).
	   Pure, no I/O, unit-tested. Fork on where overrides persist:
	   (a) NSUserDefaults keyed by bundle ID, like the ignore list;
	   (b) the existing `CDRUpdateStateStore` plist.
	   Recommend (a): preferences are not update memory and must survive
	   the store's retention TTL.
	3. Interest-scheme semantics: a preset sets `shownTypes` (Normal user:
	   all but Security and Fixed collapse? — read the PNG: Normal user
	   = "Security and fix details collapse" ⇒ Security off; decide whether
	   Fixed is off too and recommend). Editing a checkbox after choosing a
	   preset leaves the radio on the preset but marks it "customized" or
	   switches to no-preset — fork, recommend the latter with the radios
	   deselected. Developer = Everything + an `exposesDeveloperDetail`
	   flag that CND-3's right pane and CND-7 read.
	4. The 3-day step: extend `CDRSoakDuration` (enum, interval, token
	   "3d") without disturbing existing tokens or `CDRUpdatePolicyTests`.
	5. Per-app popover: `NSPopover` anchored to the header button, tri-state
	   segmented controls, the summary-line generator (pure function from
	   global + override → string, tested), Reset to Settings removes the
	   override entirely.
	6. Retracted is always shown and always a hold trigger — rendered
	   checked+disabled in both grids. Confirm the resolver enforces it
	   regardless of stored values (garbage-tolerant).
	7. Propose the fix file by file, including tests for the resolver, the
	   defaults round-trip, the 3-day soak token, and the summary line.
	Write findings to `attach/CND-4/` and flip the status.

## Out of scope
	- Acting on any of these values (CND-5, CND-7). After this ticket the
	  settings exist, persist, and resolve; nothing reads them yet except
	  CND-3's "hidden categories" one-liner, which may be wired here if
	  trivial.
	- Login item, visibility, cadence, ignore list — unchanged.

## DAT (r)
	- [ ] Settings window matches the PNG in both appearances; every control round-trips through quit/relaunch.
	- [ ] Choosing an interest scheme sets the Shown categories grid; editing a checkbox afterward behaves per Recon 3.
	- [ ] Retracted is checked and disabled in both grids and cannot be turned off by `defaults write`.
	- [ ] "…unless it ships an Internet Access Policy" is disabled when the parent toggle is off.
	- [ ] Per-app popover shows Follow Settings everywhere for an app with no override; changing one field marks that section OVERRIDDEN and produces the right summary line.
	- [ ] Reset to Settings removes the override and the OVERRIDDEN tags disappear.
	- [ ] Resolver tests cover: no override, partial override, full override, garbage stored values.
	- [ ] Deferral offers Off / 1 day / 3 days / 1 week and the 3-day token persists.

## Recon outcome (Cici, 2026-11-05)
	Implemented in one Fable-Protocol pass; findings and every resolved fork
	are in `attach/CND-4/recon.md`.

	Model: `CDRUpdatePreferences` (immutable, with a mutable twin),
	`CDRAppPolicyOverride` and `CDRPolicyResolver` in
	`Conductor/Engine/CDRUpdatePreferences.{h,m}`. Overrides persist in
	NSUserDefaults under `CDRAppPolicyOverrides`, keyed by bundle ID.

	Answers to the open questions in Recon 3: "Normal user" hides Security
	only (the PNG shows Fixed checked); editing a checkbox after a preset
	makes the scheme `custom` with all three radios deselected.

	Calls I made that r should look at in DAT:
	- The override has four fields (deferral, shown, hold, major stop), the
	  four the popover offers. There is no per-app network override.
	- The M3 controls live in two extra groups below the PNG's four:
	  "Conductor" (login, visibility, cadence) and "Ignored apps".
	- OVERRIDDEN appears as soon as a section's override is set, even when
	  the chosen value equals Settings.
	- The popover is 400pt wide with label-only badges so four fit across.

	Not yet in effect, by this ticket's scope: per-app deferral, holds and
	major stops (CND-5), the network toggles (CND-7).

