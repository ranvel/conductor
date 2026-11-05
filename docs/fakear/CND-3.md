---
key: CND-3
summary: Two-pane main window — app list left, developer's release notes right
status: DAT
resolution:
priority: High
fixVersion:
created: 2026-11-05
updated: 2026-11-05
session:
tags: [v2, ui, appkit, main-window]
related: [CND-2, CND-4, CND-5]
---

# CND-3 — Two-pane main window

## Context
	Read `docs/conductor-v2.md` first. Specs for this ticket:
	`ref-assets/Main window · Light@2x.png` + `Dark@2x.png` and
	`ref-assets/Empty & edge states · Light@2x.png` + `Dark@2x.png`.

	Today the main window is `CDRStatusWindowController` — a squat list of
	rows plus an activity log, scaffolding from M1. v2 replaces it with a
	two-pane window:

	Left (≈20%, min ~240pt): search field; sections NEEDS YOU / UPDATES /
	UP TO DATE; each row = icon, name, `installed → advertised` in mono,
	a state line with a glyph, and a trailing run of category dots (one
	per type present in the advertised notes, in the fixed order).
	Right (≈80%): header (large icon, name, developer, version pair, size,
	release date, "Includes 1.3" when versions were skipped, per-app
	override button, primary action); a NETWORK row (placeholder in this
	ticket — CND-7 fills it); then the notes grouped by type with badges,
	one badge per group, items stacked under it; skipped intermediate
	versions as collapsed rows beneath, with their own dots and count.
	Hidden categories (CND-4) collapse to "2 security fixes hidden · Show".

	Right-pane states when there's nothing to read (empty-states PNG):
	no apps found, everything up to date, deferred (with Keep waiting /
	Update now), retracted (amber banner), inspecting (progress + step
	list — CND-7 drives it, draw it here), stopped at a major version.

	Rendering is entirely from `CDRAppRowModel` (+ the grouped notes model
	from CND-2) so the menu bar and the window can't drift. Resist the
	pull to reach into the controller from the view.

## Recon
	Cici — where an answer forks, give lettered options with a recommendation.
	1. Map the current window: `CDRStatusWindowController`, its row views,
	   how `AppDelegate` wires it to `CDRUpdateController`, and what the
	   `CDRUpdatePresenting` conformance does there. List what survives
	   (the presenting seam, the activity log?) and what is scaffolding.
	   Fork for the activity log: (a) keep it as a separate Window menu item
	   (`CDRLogWindowController` already exists), (b) fold it into the
	   Developer interest scheme as a right-pane tab. Recommend (a).
	2. Extend `CDRAppRowModel` to carry what the new UI needs without
	   breaking `CDRAppRowModelTests`: section membership (needs-you /
	   updates / up-to-date, derived from state), the category-dot set,
	   release date, artifact size (from the manifest if present), the
	   "includes" list, and a short glyph+text state line per the PNG
	   ("Approve network access", "Held · includes a removal",
	   "1.2 was retracted", "Inspecting…", "Deferred · 2 days left",
	   "Stopped at major version", "Up to date"). New row states that
	   CND-5/CND-7 will produce (Held, StoppedAtMajor, Inspecting,
	   NeedsNetworkApproval) should be added to `CDRAppRowState` now with
	   placeholder derivation so the view is complete and later tickets
	   only wire inputs.
	3. Choose the layout technique. Fork: (a) `NSSplitViewController` with
	   an `NSTableView`/`NSOutlineView` left and a scroll-view stack right,
	   (b) hand-rolled `NSStackView`s. Recommend (a) — it gives the divider,
	   autosave, and min widths for free. Programmatic AppKit, no xib.
	4. Badge drawing: one `CDRBadgeView` (filled vs dashed, glyph, label,
	   color token) and one `CDRCategoryDotsView`. Colors as named asset
	   colors in `Assets.xcassets` with light/dark variants, keyed by
	   `CDRReleaseNoteType`, so CND-4's checkboxes and CND-6's sheets reuse
	   them. Match the PNG palette closely; exact hex from the Badge
	   vocabulary PNG.
	5. Primary action mapping from `CDRAppRowActions` to the header button:
	   Update to X / Update now / Install X (held) / Approve (network) /
	   Got it (retracted) / Check now (up to date). Keep the three-way quit
	   prompt and other `present*` calls as they are.
	6. Window title bar per the PNG: "Conductor · 7 updates · 3 need you",
	   "Checked 4 min ago", Check now, and a settings glyph that opens the
	   Settings window.
	7. Propose the fix file by file: new `Conductor/UI/` group (synchronized
	   groups pick it up — do not edit the pbxproj), what's deleted from
	   the status window, `AppDelegate` wiring, tests for the row-model
	   additions and the grouping→section mapping.
	Write findings to `attach/CND-3/` and flip the status.

## Out of scope
	- Settings and per-app override popover (CND-4) — the header's override
	  button exists but is disabled until then.
	- The NETWORK row's real data (CND-7) — draw the row, feed it "Unknown".
	- The interrupt sheets (CND-6).
	- Menu bar changes beyond whatever the row-model extension forces.

## DAT (r)
	- [ ] Window opens two-pane, left pane ≈20% at default width, divider position persists across launches; light and dark both match the PNGs.
	- [ ] Left rows show icon, name, version pair, state line, category dots in the fixed order; sections are correct for every `CDRAppRowState`.
	- [ ] Selecting a row renders its notes grouped by type with one badge per group, Notice/Removed first.
	- [ ] A 1.2 → 1.4 update shows "Includes 1.3" in the header and a collapsed 1.3 row with its dots and note count that expands.
	- [ ] Each of the six empty/edge states renders as drawn, with its buttons wired to the existing actions where they exist.
	- [ ] Search filters the left list by app name.
	- [ ] Menu bar still renders from the same row models with no behavior change.
	- [ ] `CDRAppRowModelTests` extended for section membership, dot set, and the new state lines.

## Recon outcome (Cici, 2026-11-05)
	Implemented in one Fable-Protocol pass; findings, every resolved fork and
	the list of placeholders are in `attach/CND-3/recon.md`.

	The status window is deleted. The main window is `Conductor/UI/`:
	a split view of `CDRAppListViewController` (search, sections, dots) and
	`CDRDetailViewController` (header, NETWORK row, grouped notes, skipped
	versions, state panes), rendering only from `CDRAppRowModel`.

	Calls I made that r should look at in DAT:
	- A fourth list section, NOT CHECKED, for rows that were never checked,
	  failed their check, or are ignored. The PNG has three sections and
	  doesn't draw those states; I would not file them under UP TO DATE.
	- Stopped-at-major rows sit under NEEDS YOU, as CND-5 says. The PNG
	  shows that row under UPDATES ("3 need you" there, 4 by the ticket).
	- Retraction State A is now its own row state (`Retracted`) instead of
	  `UpToDate` with a retraction line.

	Not checked by me: the live title bar and the divider position
	persisting across launches. r's own debug Conductor was running, so I
	did not start a second instance beside it. Panes were checked from
	renders written by `CDRMainWindowTests` to `$TMPDIR/CDRRenders/`.

