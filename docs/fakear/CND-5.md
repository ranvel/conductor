---
key: CND-5
summary: Policy — hold for manual install by category, stop at major versions, per-app deferral
status: DAT
resolution:
priority: High
fixVersion:
created: 2026-11-05
updated: 2026-11-05
session:
tags: [v2, policy, deferral, state-model]
related: [CND-2, CND-3, CND-4]
---

# CND-5 — Update policy: holds, major-version stops, per-app deferral

## Context
	Read `docs/conductor-v2.md` first. CND-2 gives you typed notes, CND-3
	gives you row states and empty-state panes, CND-4 gives you resolved
	per-app preferences. This ticket makes `CDRUpdatePolicy` honor them.

	Three behaviors:

	Hold for manual install. If the advertised release (or any skipped
	intermediate release) contains a note whose type is in the user's
	`holdTypes`, the update is surfaced but never auto-installed — it
	needs a deliberate click. Row state Held, state line "Held · includes
	a removal" (name the first held type in fixed order). The held-sheet
	(CND-6) opens from the header button; this ticket only produces the
	decision and row state.

	Stop at major versions. If `stopAtMajor` resolves true and the
	advertised version's first component is greater than the installed
	one's, the update is surfaced as StoppedAtMajor with "Always allow
	for this app" (writes a per-app override, CND-4) and "Install 1.0".
	Note the PNG's example is 0.9 → 1.0: "major" means the leading
	component changed, not "≥ 1.0".

	Per-app deferral. `CDRUpdatePolicy` currently takes one global
	`soakDuration`; CND-4 now resolves it per app. Thread the resolved
	value through and update the comment and `docs/deferral.md`.

	Interaction rules (pre-answered):
	- Urgency bypasses deferral, as today. It does NOT bypass a hold or a
	  major stop — those are the user's explicit choices; urgency is the
	  vendor's claim.
	- Deferral is evaluated first (hidden is hidden); hold and major stop
	  apply to surfaced updates only.
	- A Retracted row is always a hold (Retracted is always in holdTypes).
	- "Install anyway" on a held or stopped update marks notified exactly
	  as a normal install consent does, so retraction loudness still
	  applies afterward.

## Recon
	Cici — where an answer forks, give lettered options with a recommendation.
	1. Map `CDRUpdatePolicy.decisionForRegistration:…` and
	   `CDRUpdatePolicyTests` (the state-table tests are the contract —
	   extend, never rewrite). Map how `CDRUpdateController` turns a
	   decision into an operation and where auto-install (if any) is
	   triggered versus user-consented install.
	2. Extend `CDRUpdateOutcome` with `Held` and `StoppedAtMajor` (and the
	   decision with `heldTypes` + `stopReason`), or model them as flags on
	   `Available`. Fork; recommend new outcomes — every row of the state
	   table maps to exactly one outcome today and that property is worth
	   keeping.
	3. Change the policy signature to take the resolved
	   `CDRUpdatePreferences` (CND-4) in place of `soakDuration:`. Keep a
	   thin shim for existing tests or update their call sites — recommend
	   updating the tests.
	4. Major-version comparison: add a `CDRVersion` helper
	   (`majorComponentOf:`) with tests for `1.9 → 1.10`, `0.9 → 1.0`,
	   `2.0.1 → 3`, and non-numeric leading components (treat as not-major).
	5. Row model: wire Held / StoppedAtMajor derivation in `CDRAppRowModel`
	   (placeholders from CND-3), the state lines, section membership
	   (both are NEEDS YOU), and the header actions. Connect the empty-state
	   panes' buttons: Keep waiting / Update now (deferred), Always allow
	   for this app / Install X (major).
	6. Update `docs/deferral.md` (per-app override, 3-day step, "urgency
	   does not bypass holds") and fix the stale comment on
	   `CDRSoakDurationDefaultsKey` / `CDRSoakDuration`.
	7. Propose the fix file by file with tests: new state-table rows for
	   Held × {deferred, matured, urgency}, StoppedAtMajor × {deferred,
	   urgency}, Held+StoppedAtMajor together (recommend: major stop wins
	   for the state line, both gates must be passed to install).
	Write findings to `attach/CND-5/` and flip the status.

## Out of scope
	- The held sheet and retraction sheet (CND-6).
	- Anything network-related (CND-7).
	- Changing deferral's clock semantics (first_seen stays observation-
	  based, never vendor-dated).

## DAT (r)
	- [ ] An update whose notes include a `removed` item (with Removed in holdTypes) shows as Held under NEEDS YOU and does not install until clicked.
	- [ ] Removing Removed from holdTypes (globally or per app) releases that hold on the next check.
	- [ ] A 0.9 → 1.0 update with Stop at major versions on shows the stopped pane; "Always allow for this app" writes an override and the update proceeds normally on the next check.
	- [ ] A 1.9 → 1.10 update is not a major stop.
	- [ ] A per-app deferral of 1 week holds an app while the global setting is Off; Check now still breaks through.
	- [ ] An `urgency` manifest bypasses deferral but still lands in Held when a hold type is present.
	- [ ] Installing a held update then seeing the vendor retract it produces the loud retraction notice (notified was marked).
	- [ ] `CDRUpdatePolicyTests` covers every new state-table row; existing rows unchanged.

## Recon outcome (Cici, 2026-11-05)
	Implemented in one Fable-Protocol pass; findings, every resolved fork and
	a DAT-line → test table are in `attach/CND-5/recon.md`.

	Recon 1 finding worth knowing: nothing auto-installed before this ticket
	either — every install was already a click. So a hold is enforced by
	what can reach Install: a held or stopped update gets a notification
	with no Install button, and sits under NEEDS YOU.

	The policy takes the app's resolved `CDRUpdatePreferences`. New outcomes
	`Held` and `StoppedAtMajor`; when both apply the outcome is
	`StoppedAtMajor` and `heldTypes` is still set. A hold looks at the
	advertised release and every skipped release the user would also take.

	Calls I made that r should look at in DAT:
	- A preference change re-decides pending updates at once (no fetch, no
	  notification), not at the next check.
	- "Update now" on the deferred pane is consent without the old dialog.
	  If the update is also held or stopped, it moves to that gate instead
	  of installing.
	- Held + stopped together: the stopped pane's Install starts the install
	  in this ticket; the held sheet that makes it two confirmations is
	  CND-6.
	- `docs/spec.md` §8 was updated as well as `docs/deferral.md`, since it
	  stated the old durations and "global".

