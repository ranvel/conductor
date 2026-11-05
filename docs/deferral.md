---
title: Conductor — Update Deferral (Soak Time)
status: Implemented (M2); amended by v2 (CND-4, CND-5)
created: 2026-07-19
updated: 2026-11-05
tags: [conductor, deferral, soak, ux, spec]
related: [retraction.md, replace-flow.md]
---

# Update Deferral (Soak Time)

User-defined setting: updates are **ingested immediately but hidden from
the user** until the version has existed for the chosen duration.
Rationale: let other people find the bad builds first.

Setting: **Off / 1 day / 3 days / 1 week.** Settings holds one value for
all managed apps, and any app may override it.

*	**Per-app override (v2).** From the app's detail header the user can
	set that app to *Never* defer or to defer *1 week*, or leave it on
	*Follow Settings*. The override is a preference, stored with the
	other per-app overrides in NSUserDefaults — not in the update-state
	store, whose records expire. This amends v1's "one global value, no
	per-app overrides".
*	The policy is always handed the value **resolved for the app it is
	deciding about** (the override if there is one, otherwise Settings).
	Nothing else about deferral changes: same clock, same state model.
*	Changing the value — in Settings or for one app — re-decides pending
	updates at once, from the manifest already in hand. A longer
	deferral re-hides an update that was not yet surfaced; one that was
	already surfaced stays surfaced (the promise was made).

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
	disable or shorten the app's deferral, and it does not exempt the
	app from future ones.
*	**"Update now" (v2).** The deferred pane in the main window offers
	*Keep waiting* and *Update now*. *Update now* is the same consent
	without the dialog: it marks the version `last_notified_version`
	and the update is then decided like any surfaced one. If one of the
	user's gates applies (below), the row moves to that gate instead of
	installing.
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

## The user's gates: holds and major-version stops (v2)

Deferral decides **when** an update is surfaced. Two further settings
decide whether a surfaced update needs a deliberate install:

*	**Hold for manual install.** If the advertised release — or any
	skipped intermediate release the user would also be taking —
	contains a note whose type is in the user's hold categories
	(default: Notice, Removed, Retracted), the update is surfaced as
	*Held* and installs only when the user chooses it.
*	**Stop at major versions.** If enabled and the advertised version's
	leading component is greater than the installed one's (`0.9 → 1.0`
	is major; `1.9 → 1.10` is not), the update is surfaced as *Stopped
	at major version*. "Always allow for this app" writes a per-app
	override.

Order and interactions:

*	**Deferral is evaluated first — hidden is hidden.** A still-deferred
	update is not checked against either gate and is not marked
	notified. Gates apply to surfaced updates only.
*	When both gates apply, the major stop takes the state line; the
	update still carries its held categories.
*	A held or stopped update **is** surfaced, so it is marked
	`last_notified_version` exactly like an Available one. Retraction
	loudness therefore applies to it whether or not it was installed.
*	Release notes come from the unauthenticated manifest. A gate can
	only ever ask for one more click; it is never a verification input,
	and a forged `retracted` note cannot create a hold (a manifest may
	not carry that type at all).

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
*	**Urgency does not bypass a hold or a major-version stop (v2).**
	Urgency is the vendor's claim; the gates are the user's explicit
	choices. An urgent update skips the deferral window and then lands
	in *Held* or *Stopped at major version* like any other surfaced
	update.
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
