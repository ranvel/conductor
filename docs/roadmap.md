---
title: Conductor — Project Roadmap
status: Living document
created: 2026-07-20
updated: 2026-07-20
tags: [conductor, roadmap, planning]
related: [replace-flow.md, deferral.md, retraction.md, dev-mode.md]
---

# Roadmap

Milestone numbering starts here — M1 was named retroactively (it was built
before this document existed). Each milestone is shippable to *somebody*:
M1 to us, M2–M3 to brave friends, M4 to vendors, M5 to the public.

## M1 — The replace engine ✅ (2026-07-20)

The verify → stage → quit → swap → dequarantine pipeline from
replace-flow.md, exercisable end-to-end via dev mode against localhost.

Delivered: `CDRUpdateOperation` + engine classes, Team ID pinning
(`CDRCodeSignature`), spctl notarization gate, atomic same-volume swap,
pre-swap dequarantine, scan-based discovery, dev-mode session, minimal
status-window UI, conductor.json + manifest v1 schemas, TestHarness with
adversarial artifacts (replay, ad-hoc, downgrade, wrong-bundle), 51 tests.

Carried decisions: refuse unsigned/ad-hoc; DMG + zip by content sniffing;
no `kSecCSCheckNestedCode` (one constant to revisit); spctl shell-out
confined to one class; quarantine stripped pre-swap so the swap is the sole
mutation of /Applications.

~~Known gap~~ closed (2026-07-20): testee artifacts notarized via
`TestHarness/build-testee.sh --notarize`; the integration tests auto-detected
the stapled artifacts and now assert the full positive path (actual swap),
including the update-on-quit park/swap and cancel cases.

## M2 — Memory: deferral + retraction

The per-app state model both specs share (deferral.md amends retraction.md):
`last_seen_version` + `first_seen` per version, `last_notified_version`,
persisted in one plist under Application Support.

- Soak setting (Off / 1 day / 1 week, global), keyed on locally-observed
  `first_seen`. Version skipping during soak (vX+2 supersedes soaking vX+1).
- Retraction detection as a transition against `last_notified_version`:
  State A (notified, not installed) → clear + loud message; State B
  (retracted build installed) → inform, never auto-downgrade, persist until
  the manifest advertises ≥ installed. Silent drop for never-surfaced
  versions.
- Per-app "Check Now" break-through with the honest "deferred until <date> —
  install anyway?" presentation.
- Urgency tokens act (skip soak only) — parsing shipped in M1.
- Decide here: state retention duration, State B re-show cadence (lean:
  re-shown once per launch + passive indicator, never a nag timer).

Exit: unit tests for every transition in the two docs' state tables; an e2e
retraction drill using the harness (promote 1.1, notify, swap manifest back
to 1.0, observe State A loudness; install first for State B).

## M3 — The product: menu bar app (+ windowed UI)

Grow the milestone status window into a first-class windowed UI and add an
*optional* menu bar presence. Both surfaces render one shared per-app row
model. Menu-bar residency and Dock presence are each user choices (Settings)
— some users only want a windowed app; a spot in their menu bar is theirs to
grant, not ours to take. The app can never be made invisible (at least one
surface stays on), and dev mode forces the status item visible for the
session.

- Menu bar presence: status item, per-app update list, badge on available
  updates; dev-mode icon variant (the unmissable state dev-mode.md requires).
- Scheduled background scans (timer + wake/network-change triggers), user
  notifications via UNUserNotificationCenter.
- "Update on quit" (deferred from M1): observe termination, then swap.
- Login item (SMAppService), Settings window (soak duration, scan cadence,
  per-app ignore).
- Error surfaces: vendor URL escape hatch everywhere replace-flow.md says
  "surface the vendor URL and stop."

Exit: Conductor runs for a week as a login item managing the testee (and
muwav, dogfooding) without a manual scan.

## M4 — The spec + adoption kit

Turn the internal design into something a stranger can adopt.

- Public spec document: conductor.json + manifest schema (frozen at v1),
  verification guarantees, the "no hooks" rationale from replace-flow.md
  near-verbatim, vendor guidance (fallback caching, recall-by-re-pointing,
  artifact requirements).
- Vendor quickstart + a reference `release.py`-style snippet emitting the
  manifest; sha256 helper.
- muwav adopts for real: conductor.json into its bundle pre-sign (change
  lives in muwav-release), manifest served alongside the existing MUW-146
  `latest.json` (which stays, per MUW-145, as the no-Conductor fallback).
- Revisit with field data: DMG-only vs both formats; explicit `recalled`
  manifest field (retraction.md open question — only if State B messaging
  proves too vague without a vendor reason string).

Exit: a developer who has never seen this repo integrates a test app using
only the public docs.

## M5 — Hardening + v1.0 distribution

- Conductor's own distribution: signed, notarized DMG + its own manifest.
  Self-update remains **notify-only** (replace-flow.md invariant — sized L,
  deliberately out of the engine).
- EPERM/root-owned apps: measure frequency in the field; only then decide on
  the SMAppService privileged helper (do not build speculatively).
- `kSecCSCheckNestedCode` benchmark on large real-world bundles; flip the
  constant or document why not.
- Per-app scan cadence configuration: v1 ships one global cadence (M3);
  revisit with dogfood feedback. Distinct from per-app *soak* overrides,
  which remain explicitly not planned.
- Edge inventory: App Translocation on Conductor itself, /Applications on
  unusual volumes, case-sensitive filesystems, multiple copies of a managed
  app, Gatekeeper policy changes in future macOS.
- Accessibility + localization pass on all user-facing copy.

Exit: v1.0 tag, public release.

## Explicitly not planned

Per-app soak overrides, custom soak durations, vendor post-install hooks
(never), automatic downgrade (never), patching inside bundles (never),
managing unsigned apps, installer-package territory (kexts, system
extensions, privileged helpers as a product feature).

## Ordering rationale

M2 before M3 because the state model changes what the UI must display
(deferred vs available vs retracted are different list rows); building the
menu bar app first would mean rebuilding its data layer immediately after.
M4 after M3 because the spec should describe software that exists — writing
it earlier invites promising behavior the product doesn't have yet. M5 last
because hardening decisions (privileged helper, nested-code cost) want field
data from M3–M4 dogfooding.
