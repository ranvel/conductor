---
key: CND-6
summary: Interrupt sheet component — held-for-manual-install and retraction variants
status: DAT
resolution:
priority: Medium
fixVersion:
created: 2026-11-05
updated: 2026-11-05
session:
tags: [v2, ui, appkit, sheets]
related: [CND-3, CND-5, CND-7]
---

# CND-6 — Interrupt sheets

## Context
	Read `docs/conductor-v2.md` first. Spec for this ticket:
	`ref-assets/Interrupt sheets · Light@2x.png` + `Dark@2x.png`.

	Four moments stop the user; the PNG shows all four. They are one sheet
	component with variants, so that a user who has seen one recognizes
	the next. This ticket builds the component and wires the two variants
	whose inputs already exist after CND-5:

	Held for manual install: "SmoothMove 1.4 is waiting for you / Held
	because it includes a removal." The offending notes rendered with their
	badges, a line naming the user's hold categories with a "Change in
	Settings" link, Not now / Install 1.4 (Install is the default button —
	the user already chose to open this).

	Retraction: amber header with the ↩ glyph, "Developer retracted 1.2 /
	You have the latest build.", one line of plain explanation naming the
	app, OK. This is retraction State A's loud notice (retraction.md),
	currently delivered through `presentRetractionNotice:` and
	`notifyRetractedPending:` as plain text — it becomes this sheet when
	the window is frontmost and stays a user notification otherwise.

	The two network variants (gains access · ships a policy / gains access ·
	no policy) are CND-7's; build the component so they drop in: a
	header (icon, title, subtitle), an optional monospace "entitlements
	diff" block, an optional two-column policy table, an optional amber
	warning strip, a footer with secondary + default button. The safe
	choice is always the default button — per variant: Install (held, the
	user opened it), OK (retraction), Approve (policy present), Skip
	(no policy).

	Sheets drop from the main window (`beginSheet:`). They respect the
	`CDRUpdatePresenting` split: these are `present*`-class moments (the
	user clicked something, or a check just completed with the window
	open), never fired from a background check with the window hidden.

## Recon
	Cici — where an answer forks, give lettered options with a recommendation.
	1. Map every `present*`/`notify*` call site in `CDRUpdateController`
	   and the two presenter implementations (window / menu bar / user
	   notifications). Confirm the rule "modal only inside a user-started
	   flow" and decide how a retraction found by a background check reaches
	   the sheet: fork (a) sheet only if the window is key, else
	   notification + persistent row banner (the empty-state pane from
	   CND-3), (b) always notification, sheet only when the user clicks the
	   row. Recommend (a).
	2. Design `CDRInterruptSheetController` (one `NSWindowController` per
	   presentation, a value-object `CDRInterruptSheetModel` with the
	   optional sections above, buttons as `{title, isDefault, action}`).
	   Reuse `CDRBadgeView` and the asset colors from CND-3.
	3. Wire Held: the detail header's "Install 1.4" on a Held row opens
	   the sheet instead of installing; Install from the sheet proceeds
	   through the normal consent path (`noteNotifiedVersion:` etc.).
	   "Change in Settings" opens Settings scrolled to the Install-manually
	   group (CND-4 — a `showSection:` hook on the settings controller).
	4. Wire Retraction State A to the sheet per Recon 1; keep State B
	   (recalled build installed) as the persistent row line + vendor link,
	   unchanged.
	5. Add a `present` entry point for CND-7's variants to the protocol now
	   (`presentNetworkApprovalForAppNamed:… diff:policy:completion:`) with
	   a stub implementation, so CND-7 only fills it.
	6. Propose the fix file by file; the sheet model and its "which button
	   is default" rule are pure and tested; the controller gets a snapshot-
	   free smoke test that each variant lays out without throwing.
	Write findings to `attach/CND-6/` and flip the status.

## Out of scope
	- Entitlement diffing, the Internet Access Policy table's data, and the
	  network variants' wiring (CND-7). Build the sections, feed them nil.
	- Changing the three-way quit prompt or the relaunch offer.

## DAT (r)
	- [ ] Clicking Install on a Held row opens the held sheet with the held notes badged, the hold-categories line, and Install as the default button.
	- [ ] Not now leaves the row Held; Install proceeds and marks notified.
	- [ ] "Change in Settings" opens Settings at the Install-manually group.
	- [ ] A retraction (State A) found while the window is key shows the amber sheet; found while hidden, it posts the notification and the row/pane show the amber banner.
	- [ ] Light and dark match the PNG; Escape = secondary button, Return = default.
	- [ ] The network variants render from a model with a diff block, a policy table, and a warning strip (fed test data), even though nothing produces that data yet.

## Recon outcome (Cici, 2026-11-05)
	Implemented in one Fable-Protocol pass; the present/notify map, every
	resolved fork and a DAT-line → test table are in
	`attach/CND-6/recon.md`.

	One component, `CDRInterruptSheetController`, draws all four variants
	from a pure `CDRInterruptSheetModel`. Held and Retraction are wired; the
	two network variants render from test data and have their presenter
	entry point for CND-7.

	Calls I made that r should look at in DAT:
	- Retraction sheet: only when the user started the check (or the
	  install) AND the window is key. A scheduled check is always
	  notification + banner, even with the window key. This is narrower than
	  Recon 1 option (a), to keep the "no modals from passive checks" rule.
	- The amber banner persists until "Got it" / OK, across checks and
	  relaunches, through a small notice store in NSUserDefaults. The
	  policy's one-time retraction memory is unchanged.
	- A stopped-at-major update that also carries a hold goes through the
	  held sheet too (the second confirmation CND-5 left open).
	- `presentRetractionNotice:vendorURL:` is gone from the protocol,
	  replaced by `presentRetractionForAppNamed:…completion:`.

	Not covered by a test: the "Change in Settings" hop into Settings, and
	the is-the-window-key branch, both in `AppDelegate`.

