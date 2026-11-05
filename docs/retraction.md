---
title: Conductor — Update Retraction Handling
status: Implemented (M2); State A presentation amended by v2 (CND-6)
created: 2026-07-19
updated: 2026-11-05
tags: [conductor, retraction, recall, manifest, spec]
related: [replace-flow.md, MUW-145]
---

# Update Retraction Handling

Scenario: developer publishes vX+1 → Conductor notifies the user →
developer retracts vX+1 (cf. `release.py recall`). Conductor must fail
**loudly** — a silently vanishing update badge reads as a bug and erodes
trust in exactly the tool whose product is trust.

## Detection requires memory

A retraction is only observable as a **transition**, so Conductor keeps
per-app state (see deferral.md for the full state model — deferral splits
this into `last_seen_version` and `last_notified_version`):

*	`last_notified_version` — the newest version Conductor has actually
	**surfaced to the user** for this app
*	`notified_at` timestamp

Retraction event = a fresh manifest whose latest version is **lower than
`last_notified_version`**. Loud messaging is owed only for versions the
user was told about; a version retracted while still soaking (never
surfaced) is dropped **silently**. Without stored state, a retracted
update is indistinguishable from "there was never an update," and the
loud failure is impossible.

## The two user states

**State A — notified, not yet installed** (the common case):

*	Clear the pending update.
*	Loud, plain message:
	*"<App>: the developer retracted update <vX+1>. You already have the
	latest build (<vX>)."*
*	Offer the vendor URL / changelog link so the curious can find out why.

How State A reaches the user (v2):

*	**The loud message fires once.** The decision that detects the
	retraction clears `last_notified_version`, so no later check
	announces it again. That is unchanged.
*	**Where it appears depends on who started the check.** A scheduled
	check posts a user notification and never raises anything modal. A
	check the user asked for ("Check now"), or an install whose
	last-moment re-check found the update withdrawn, shows the amber
	retraction sheet — but only if the main window is key; otherwise it
	falls back to the same notification.
*	**The row keeps an amber notice until it is acknowledged.** The
	detection is one-time, but the user may not have seen it: the app's
	row says "<vX+1> was retracted" and its pane shows the banner (with
	the dates the version was surfaced and pulled) across later checks
	and relaunches, until the user presses *Got it* / *OK*. This is
	presentation state, stored beside the other preferences — the
	policy and its state store are not involved, and it is never a
	policy input.
*	The notice is dropped without being acknowledged when it becomes
	moot: the developer advertises something newer, or the withdrawn
	build turns out to be installed (State B takes over).

**State B — already installed the retracted build:**

*	Installed version > manifest latest. Conductor must **inform, never
	auto-downgrade** (rationale below).
*	Message: *"<App>: the developer recalled build <vX+1>, which you have
	installed. Conductor does not downgrade automatically — check the
	developer's site for guidance."* + vendor URL.
*	This state persists (re-shown, not re-nagged) until the manifest
	advertises a version ≥ installed again (the vendor ships vX+2 or
	re-promotes).

## Why no automatic downgrade — even for a legitimate recall

The downgrade-refusal check in replace-flow.md §3.2 is load-bearing
against replay attacks: an attacker with a hijacked update URL serving an
*older, validly signed, vulnerable* build. The manifest is **not
authenticated** (no key ceremony — that's the point of the design), so
any "please downgrade" signal in the manifest is also an attacker's
downgrade lever. A recall field cannot be distinguished from a replay
attack by Conductor; therefore recalls route through the human. The
vendor's remedy for a bad build is shipping vX+2 — which is also what
they'd tell manual-download users, so this stays consistent with the
"apps must survive drag-and-drop updates" principle.

## Last-moment re-check

Between notification and the user clicking "install," hours may pass.
Re-fetch the manifest immediately before beginning the download/install
flow. If the advertised version dropped in the meantime → State A message,
abort cleanly. Cheap insurance for exactly the window R described.

## Primary vs fallback staleness

The fallback URL can serve a stale manifest (CDN cache) that still
advertises the retracted version while the primary shows the recall.
Rule: **if the primary update URL is reachable, its manifest wins,
always.** The fallback exists for unresponsiveness only, never as a
second opinion. Spec should say this explicitly so vendors host the
fallback accordingly (and are warned about cache TTLs).

## Open questions

*	Explicit `recalled: [versions]` manifest field? Pro: lets Conductor
	distinguish a deliberate recall from a vendor's manifest mistake, and
	lets State B carry a vendor-authored reason string. Con: schema
	surface, and the transition-detection above already works with zero
	schema additions. Leaning: **start without it**; the loud message is
	achievable from state alone. Revisit if muwav's own `dangerous` field
	proves its worth in practice.
*	How long to retain per-app notification state, and where (plist in
	Application Support, presumably).
*	State B nag cadence: on every scan, or once + a passive menu bar
	indicator?
