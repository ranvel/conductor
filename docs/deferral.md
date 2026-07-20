---
title: Conductor — Update Deferral (Soak Time)
status: Draft (design, pre-implementation)
created: 2026-07-19
updated: 2026-07-19
tags: [conductor, deferral, soak, ux, spec]
related: [retraction.md, replace-flow.md]
---

# Update Deferral (Soak Time)

User-defined global setting: updates are **ingested immediately but
hidden from the user** until the version has existed for the chosen
duration. Rationale: let other people find the bad builds first.

Setting: **Off / 1 day / 1 week.** One global value for all managed apps.
No per-app overrides in v1 (don't build speculatively).

## Clock semantics: first-seen, locally

The soak clock starts at **`first_seen`** — the timestamp when *this*
Conductor instance first observed the version in a manifest. Not a
vendor-supplied publish date:

*	The manifest is unauthenticated; a publish date in it can be
	backdated to defeat the soak.
*	`first_seen` is locally verifiable and needs no schema addition.
*	Cost: a user whose Mac was asleep for a week gets "late" soak
	starts. Acceptable — the feature is a probabilistic filter, not a
	contract.

## State model (amends retraction.md)

Deferral splits "advertised" into two distinct facts per app:

*	`last_seen_version` + `first_seen` timestamp per version —
	newest version Conductor has *observed*
*	`last_notified_version` — newest version Conductor has *surfaced
	to the user*

Consequences:

*	**Deferral** keys on `first_seen`: notify when
	`now - first_seen >= soak duration`.
*	**Retraction loudness** keys on `last_notified_version` only. If a
	version is retracted *during* its soak window — never surfaced —
	Conductor drops it **silently**. No promise was made, so no loud
	correction is owed. (This is the recall-filter synergy: with a
	1-week soak, most recalled builds live and die without the user
	ever knowing.)

## Break-through: "the new hotness now"

Scenario: user sees the dev announce the new version on social media and
wants it immediately, mid-soak.

*	An **explicit, per-app** "Check Now" action bypasses deferral for
	that app: Conductor fetches the manifest fresh, and shows whatever
	is advertised — including a still-soaking version.
*	Presentation should be honest, not naggy:
	*"<App> <vX+1> is available (deferred until <date> by your update
	settings). Install anyway?"*
*	Installing a soaking version via break-through marks it
	`last_notified_version` — retraction loudness now applies to it
	like any surfaced update.
*	Break-through is **per-app and per-invocation**. It does not
	disable or shorten the global soak, and it does not exempt the app
	from future soaks.
*	The global "check all apps now" action does **not** break through —
	only a deliberate act on a specific app expresses "I want this
	one now." (Otherwise every manual scan defeats the feature.)

## Interactions

*	**Last-moment re-check** (retraction.md) still runs on break-through
	installs. Soak bypass never bypasses verification — replace-flow
	§3 applies unconditionally.
*	**Version skipping during soak:** if vX+1 is soaking and vX+2
	appears, vX+2 gets its own `first_seen` and its own soak; when it
	matures, notify about vX+2 only. vX+1's entry is superseded —
	never notify about a version that is no longer the latest.

## Urgency flag: soak bypass with fixed vocabulary

A manifest MAY carry an urgency token that bypasses the soak window
(notify immediately). Design constraint that makes it abuse-resistant:
the token comes from a **closed, Conductor-defined enum of scary
reasons** — no dev-definable text, and deliberately no mild option:

*	`system_risk` — fixes a vulnerability that puts the system at risk
*	`data_loss` — fixes a bug that can cause data loss
*	`data_exfiltration` — fixes a potential data exfiltration issue

Why this shape:

*	**No free text, no soft option.** Conductor renders its own fixed
	copy per token; the manifest carries only the token. A dev cannot
	write marketing prose into the alert, and the only available words
	are admissions ("<App> has a data loss bug"). Invoking the flag is
	reputationally expensive unless it's true — the enum polices
	itself.
*	**Attribution in the copy.** Rendered as vendor-declared:
	*"The developer has flagged <App> <vX+1> as fixing a bug that can
	cause data loss."* The manifest is unauthenticated, so a hijacked
	URL could attach a false scary flag to a legitimate update; framing
	it as the developer's claim (and the flag doing nothing except
	skipping soak) bounds the damage to embarrassment, not compromise.
*	**Bypasses soak only.** Verification (replace-flow §3), the
	last-moment retraction re-check, and user consent to install are
	all unconditional. Urgency accelerates notification of a validly
	signed vendor build; it changes nothing else.
*	**Unknown tokens are ignored** (treated as no flag). Forward
	compatibility: a future enum addition must not cause older
	Conductors to render text they don't have copy for.
*	Valid only on the latest advertised version; an urgency-surfaced
	update counts as notified, so retraction loudness applies to it
	normally.

## Open questions
*	Custom durations beyond 1d/1w? Not v1. Two values + Off covers the
	stated need.
*	Where the per-app state lives (shared plist with retraction state,
	Application Support) — decide at implementation, one file for both.
