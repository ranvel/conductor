# CND-2 recon — manifest release notes

Cici, 2026-11-05. Fable Protocol: recon, solutioning and implementation ran
as one pass; this file records what was found and every fork that was
resolved, so the code can be checked against it.

## Outcome

Implemented. A manifest may now carry `notes`, `released`, `size` and
`history`. Parsing ends at a typed, grouped model in the engine; nothing
renders yet (CND-3). No verification, download or swap code changed.

## Decision r made: where note history lives (Recon 2)

The ticket recommended (b) a `releases` array. The Badge vocabulary PNG shows
a top-level `notes` array next to `version`. r chose a third shape:

	{
	  "version": "1.4",
	  "released": "2026-11-03",
	  "notes":   [ {"type": "notice", "text": "…"} ],
	  "history": [ {"version": "1.3", "date": "2026-10-14", "notes": [ … ]} ]
	}

- Top-level `notes` + `released` always describe the advertised `version`,
  matching the PNG.
- `history` holds earlier versions only. There is no duplicated version to
  keep in sync, so the ticket's "`releases[0].version` MUST equal `version`"
  rule has no equivalent.
- The ticket's rendering rule carries over unchanged: Conductor shows an
  entry only when it is strictly newer than installed and strictly older
  than advertised. Option (c) (remember notes locally) stays rejected.

## Findings

1. **Parser and unknown-key policy.** `CDRManifest.m` reads a fixed set of
   keys and ignores everything else; there is no allowlist. spec.md §1
   (lines 47–51) says unknown keys are ignored so additive evolution needs
   no version bump. Confirmed: `conductor_manifest` stays `1`.
2. **`CDRUrgency` precedent.** The urgency token mapping is one-way (string →
   enum) and inline in the parser. The note vocabulary needs both directions
   (CND-4 persists type sets), so the round-trip lives in
   `CDRReleaseNote.m` as `CDRReleaseNoteTypeKey` / `CDRReleaseNoteTypeFromKey`.
3. **No size or date field existed.** CND-3's header shows both
   ("18.4 MB", "Released Nov 3, 2026"), so `size` and `released` were added
   here, where the schema work is, instead of reopening the spec in CND-3.
4. **`docs/spec.md` numbering.** §3 ended at §3.4; §3.5 was free. The
   one-advertised-version rule is in §3.3, not a section of its own.
5. **The harness was gone.** Commit `188f661` deleted `TestHarness/`
   (`build-testee.sh`, `testee-main.m`, `.gitignore`). r approved restoring
   it from `188f661^` and running it with `--notarize`.

## Forks resolved

| Fork | Chosen | Why |
|---|---|---|
| Recon 2: history shape | top-level `notes` + `history` | r's call, above |
| Recon 3: unknown `type` | (b) drop, log, count | degrades safely on an older Conductor without hiding that something was said |
| Recon 3: `retracted` from a manifest | same as unknown | never rendered as a Retracted row |
| Recon 3: text rules | collapse whitespace, trim, cap 500 with `…` | as recommended; the cut never splits a composed character |
| Where the parser logs | it doesn't: `parseWarnings` on the manifest, logged by `CDRUpdateController` per check | keeps the parser pure and the warnings testable |
| Malformed `notes` / `history` block | ignored with a warning | display data must never fail a manifest |
| What counts as "undisplayable" | only items whose `type` is a string Conductor won't render | a malformed item (no type, no text) said nothing nameable, so it is logged but not counted |
| `released` / `date` form | `YYYY-MM-DD`, stored as local noon | the day the vendor wrote is the day every time zone shows |

## Things I added that the ticket did not ask for

- **`size` and `released` keys** (finding 3).
- **A cap of 100 notes per version**, alongside the ticket's cap of 10
  history entries. Both are constants in `CDRManifest.h` and documented in
  §3.5.
- **`CDRReleaseNoteTypeSet`**, a bitmask of types, because CND-3 (category
  dots) and CND-4 (shown / held categories) both need "which types".
- **`testHarnessManifestExercisesReleaseNoteRules`**, an integration test
  that fetches the harness manifest through the real fetcher.

## What changed

- `Conductor/Engine/CDRReleaseNote.{h,m}` — new: `CDRReleaseNoteType` (enum
  order is render order), `CDRReleaseNoteTypeSet`, key ↔ enum, display
  names, `CDRSanitizedReleaseNoteText`, `CDRReleaseNote`,
  `CDRReleaseNoteGroup`, `CDRGroupReleaseNotes`, `CDRRelease`.
- `Conductor/Engine/CDRManifest.{h,m}` — `advertisedRelease`, `history`,
  `artifactSize`, `parseWarnings`, `-releasesNewerThanVersion:`.
- `Conductor/CDRUpdateController.m` — logs `parseWarnings` after each fetch.
- `docs/spec.md` — §3.1 example and table, §3.3 note, new §3.5.
- `TestHarness/` — restored; `manifest.json` carries notes of all seven
  types, one unknown type, one forged `retracted`, and a three-entry
  history; the derived-manifest `sed` patterns are anchored to the
  top-level `version` line.
- `ConductorTests/CDRReleaseNoteTests.m` (new),
  `ConductorTests/CDRManifestTests.m`,
  `ConductorTests/CDRUpdateOperationIntegrationTests.m`.

## Notes for later tickets

- The property is `advertisedRelease`, not `release`: a property named
  `release` collides with `-[NSObject release]` under ARC.
- `CDRRelease.undisplayableNoteCount` is the input for the neutral one-liner
  ("1 note this Conductor can't display · see changelog") that CND-3 draws.
- The `urgent`, `downgrade`, `retracted`, `replay` and `adhoc` harness
  manifests: `manifest-urgent.json` has no notes at all (it exercises "a
  manifest without notes parses exactly as before"); the others inherit the
  main manifest's notes through `sed`.
