---
title: Conductor — Dev Mode
status: Draft (design, pre-implementation)
created: 2026-07-19
updated: 2026-07-19
tags: [conductor, dev-mode, transport, testing, spec]
related: [replace-flow.md]
---

# Dev Mode

The **sole exception** to the HTTPS-only rule (replace-flow.md §1), for
developers testing their conductor.json + manifest + artifact pipeline
from localhost without needing ngrok/TLS ceremony.

## Invocation

```
conductor --dev-mode com.ranvel.muwav
```

*	Exactly **one** bundle identifier. Repeating the flag or passing a
	list is an error, not a feature.
*	Launches the app in a dev-mode session (argument parsed at launch;
	no persistent preference, no hidden defaults key).

## Semantics

*	Conductor shows **only** the specified app. Every other managed app
	is invisible for the session — deliberately, so dev mode is useless
	as an everyday driver for people with "whatever garbage connections
	they have set up."
*	For that one app, plain-HTTP update / fallback / artifact URLs are
	permitted. The dev points their test build's conductor.json at
	`http://localhost:8000/...` and the whole notify → verify → swap
	flow is exercisable against `python -m http.server`.
*	**Session-only.** Quit and relaunch normally → normal mode, full
	app list, HTTPS-only. Dev mode is never remembered.
*	Unmissable UI state: menu bar icon variant + banner —
	*"DEV MODE — com.ranvel.muwav — insecure connections permitted."*

## What dev mode does NOT relax

Transport only. **Verification is untouched:** bundle ID match, version
sanity, signature validity, Team ID pinning, notarization, downgrade
refusal (replace-flow §3) all run exactly as in production. Rationale:

*	The point of dev mode is testing the *real* pipeline. A dev should
	be feeding Conductor the same Developer ID-signed, notarized
	artifact their `release.py`-equivalent will ship — just served from
	localhost. If verification were relaxed, dev mode would pass on
	artifacts that production rejects, which is worse than useless.
*	It keeps the security claim one sentence: dev mode changes *where*
	Conductor may fetch, never *what* it will install.
*	Ad-hoc/unsigned test builds therefore still fail — consistent with
	the "signed + notarized apps only" rule (replace-flow §0). This is
	a feature: the failure happens on the dev's machine, not a user's.

## Open questions

*	~~Restrict dev-mode HTTP to loopback addresses only?~~ **Resolved
	(2026-07-19): no host restriction.** Dev mode already carries enough
	friction (single app, session-only, relaunch-with-flag every time)
	that further fencing is unnecessary, and a real workflow needs
	public hosts: testing `http://example.com/...` before the TLS cert
	is in place, then adding the `s` with everything else unchanged.
	The dev determines their own threat model — which is a sane stance
	*because* verification is transport-independent: the worst an
	on-path attacker can do to an HTTP dev-mode session is serve a
	manifest whose artifact then fails Team ID pinning. Transport trust
	was never load-bearing; that's the whole design.
*	Should deferral/soak apply in dev mode? Leaning no — dev mode
	implies "show me now"; soak-testing can be done by setting the
	preference normally.
