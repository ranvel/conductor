---
key: CND-2
summary: Manifest release notes — typed {type, text} items with a fixed classification vocabulary
status: DAT
resolution:
priority: High
fixVersion:
created: 2026-11-05
updated: 2026-11-05
session:
tags: [v2, manifest, release-notes, spec]
related: [CND-3]
---

# CND-2 — Manifest release notes: typed items, fixed vocabulary

## Context
	Read `docs/conductor-v2.md` first; `ref-assets/Badge vocabulary · Light@2x.png`
	is the spec for this ticket.

	Today the manifest carries only `changelog_url`. v2 wants release notes
	*in* the manifest, as a list of plain-text items each tagged with one
	of seven dev-authored types (`notice`, `removed`, `disabled`, `security`,
	`added`, `improved`, `fixed`). Conductor renders the badges; devs never
	send markup. An eighth type, `retracted`, exists only as a Conductor-
	generated row and must be refused if it appears in a manifest.

	The main window (CND-3) also stacks the notes of skipped intermediate
	versions ("1.2 → 1.4 · Includes 1.3"). spec.md §3.3 says the manifest
	advertises exactly one version, so note history needs a home. This is
	the one real schema decision in the ticket — see Recon 2.

	The manifest stays unauthenticated and stays a non-security input
	(spec.md §3.2). Notes are display data. Nothing here touches the
	verification chain.

## Recon
	Cici — where an answer forks, give lettered options with a recommendation.
	1. Map `CDRManifest` parsing (`CDRManifest.m`, `CDRManifestTests.m`) and
	   the unknown-key policy. Confirm additive fields need no
	   `conductor_manifest` bump (spec.md §1 says they don't).
	2. Decide where note history lives. Fork:
	   (a) a top-level `notes` array for the advertised version only — no
	       history; skipped versions show "notes unavailable";
	   (b) a `releases` array, newest first, each `{version, date, notes}`,
	       bounded (recommend: Conductor reads at most the first 10); the
	       top-level `version`/`url`/`sha256` stay authoritative for what is
	       installable, `releases[0].version` MUST equal `version` or the
	       whole `releases` block is ignored with a log line; Conductor
	       renders entries strictly newer than the installed version and
	       strictly not newer than the advertised one;
	   (c) Conductor remembers notes it observed per version in
	       `CDRAppUpdateState` — rejected: a user who installs after a
	       deferral never observed the skipped version.
	   Recommend (b). Either way, `changelog_url` stays as the escape hatch.
	3. Define the item schema: `{"type": "<key>", "text": "<plain>"}`.
	   Text rules: plain string, trimmed, no newlines (recommend: collapse
	   whitespace, cap at 500 chars, log and truncate beyond). Decide the
	   fate of an item with an unknown `type`. Fork:
	   (a) drop the item silently;
	   (b) drop it, log it, and surface a neutral one-liner in the UI
	       ("1 note this Conductor can't display · see changelog");
	   (c) refuse the whole manifest.
	   Recommend (b): it degrades safely on an older Conductor without
	   hiding that something was said. `retracted` from a manifest is
	   always (b) — it is never rendered as a Retracted row.
	4. Model: add a `CDRReleaseNoteType` enum (the eight values, in render
	   order so sorting is `enum` order), a `CDRReleaseNote` value object,
	   and `CDRRelease` (version, date, notes) on `CDRManifest`. Keep the
	   enum's canonical lowercase key ↔ enum round-trip in one place, the
	   way `CDRUrgency` is handled.
	5. Grouping: a pure function from `[CDRReleaseNote]` → ordered groups by
	   type, in the fixed order, stable within a group. Lives in the engine
	   (no AppKit) so CND-3 renders it and tests assert it.
	6. Update `docs/spec.md`: a new §3.5 "Release notes" with the item
	   schema, the vocabulary table (key, meaning, who writes it), the fixed
	   render order, the plain-text rule, the unknown-type rule, and the
	   `releases` history rule from Recon 2. Update the §3.1 example.
	7. Update `TestHarness/build-testee.sh` manifests so v1.1 carries notes
	   of every type, plus one unknown type and one forged `retracted`, so
	   the integration harness exercises the rules.
	Write findings to `attach/CND-2/` and flip the status.

## Out of scope
	- Rendering (CND-3). This ticket ends at a parsed, grouped model.
	- Any change to verification, download, or the swap.
	- Markdown, links, or emphasis in note text — refused by design.

## DAT (r)
	- [ ] A manifest with notes of all seven dev types parses; each item has the right enum value.
	- [ ] Items come out grouped in the fixed order regardless of manifest order.
	- [ ] An item with an unknown `type` is dropped, logged, and counted; the rest of the manifest is unaffected.
	- [ ] A manifest item with `type: retracted` is dropped and logged, never rendered.
	- [ ] A manifest with no `notes`/`releases` at all still parses and installs exactly as before.
	- [ ] Skipped-version history resolves per Recon 2's chosen option, including the "entries ≤ installed are ignored" rule.
	- [ ] `docs/spec.md` §3 documents all of the above and the harness manifests exercise it.

## Recon outcome (Cici, 2026-11-05)
	Implemented in one Fable-Protocol pass; findings and every resolved fork
	are in `attach/CND-2/recon.md`.

	Schema, as r decided it (differs from Recon 2's recommendation): top-level
	`notes` + `released` describe the advertised `version`; an optional
	`history` array of `{version, date, notes}` describes earlier versions.
	There is no `releases` array, so wherever this ticket says `releases`,
	read `history`. Also added: `size` (bytes, display only) for CND-3's
	header.

	Unknown `type` and a manifest `retracted`: dropped, logged, counted
	(Recon 3 option b). Text: whitespace collapsed, trimmed, capped at 500.
	Conductor reads at most 10 history entries and 100 notes per version.

	The model CND-3 renders from: `CDRManifest.advertisedRelease`,
	`-releasesNewerThanVersion:`, `CDRRelease.groups` / `.typeSet` /
	`.undisplayableNoteCount`.

	`TestHarness/` had been deleted in 188f661; restored from 188f661^ and
	extended. Artifacts are built with `--notarize`.
