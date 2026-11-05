---
title: Conductor — Public Specification v1
status: Draft for M4 review (formats frozen at v1 on acceptance)
created: 2026-07-20
updated: 2026-07-20
tags: [conductor, spec, public, adoption]
related: [replace-flow.md, deferral.md, retraction.md, dev-mode.md]
---

# Conductor Public Specification, version 1

Conductor is a standalone macOS updater for third-party apps. This document
is the complete integration contract: what you put in your app, what you
host on your server, what your release artifacts must look like, and —
just as important — what Conductor guarantees, and what it will never do.

It is written for a developer who has never seen Conductor's source. If you
ship a signed, notarized Mac app outside the App Store, everything you need
is here.

The key words MUST, MUST NOT, SHOULD, and MAY are used as in RFC 2119.

## 1. The model in one page

Your app embeds a small static file, `conductor.json`, that says where
updates are announced. Conductor discovers managed apps by scanning
/Applications for that file, fetches each app's **manifest** (a second
small static file on your server), and when the manifest advertises a newer
version, downloads the artifact, verifies it, and atomically replaces the
installed bundle.

There is no SDK, no framework, no code change, and no vendor key material.
The trust anchor is Apple's PKI, which your app already participates in:

> **Conductor can only ever swap one signed bundle for a newer signed
> bundle from the same vendor.**

Concretely, Conductor captures the **Team ID of the installed copy** and
requires every downloaded bundle to satisfy it. A hijacked update URL or
compromised CDN yields nothing: the attacker's payload fails the pinned
Team ID check unless they also hold your Developer ID signing identity —
at which point your update channel was not the weak link. A replayed old
build (validly signed, known-vulnerable) is refused by the downgrade check,
which reads versions from the downloaded bundle itself, never from the
manifest.

Both file formats carry an integer format version and are **frozen at 1**.
Unknown keys are ignored in both files, so additive evolution never
requires a version bump; the integer changes only for breaking changes,
and a Conductor that does not support a format version refuses the file
rather than guessing.

## 2. `conductor.json` — the file in your bundle

### 2.1 Location

Exactly this path inside your app bundle:

```
YourApp.app/Contents/Resources/conductor.json
```

Add it **before you sign**. It then lives under your code seal: a tampered
`conductor.json` breaks the very signature the next update is verified
against, which is what makes an unauthenticated JSON file safe to trust
for *where to look* (and nothing else).

### 2.2 Schema (format 1)

```json
{
  "conductor": 1,
  "update_url": "https://example.com/updates/manifest.json",
  "fallback_url": "https://cdn.example.com/updates/manifest.json",
  "vendor_url": "https://example.com"
}
```

| Key            | Type   | Required | Meaning                                        |
|----------------|--------|----------|------------------------------------------------|
| `conductor`    | number | yes      | Format version. MUST be `1`.                   |
| `update_url`   | string | yes      | Absolute HTTPS URL of your manifest.           |
| `fallback_url` | string | no       | Second manifest URL, tried only when the primary is unreachable (§6). |
| `vendor_url`   | string | no       | Your homepage. Shown to users when Conductor must stop and hand off to you (both URLs dead, recalls, unfixable errors). |

Rules:

- URLs MUST be absolute, with scheme and host. `update_url`,
  `fallback_url`, and the manifest's artifact URL MUST be HTTPS. (The sole
  exception is Conductor's session-only developer mode, §9, which relaxes
  transport — never verification — for one bundle ID at a time.)
- There is deliberately **no version field** here. Your version lives in
  `Info.plist` (`CFBundleShortVersionString`, optionally `CFBundleVersion`),
  where it always did — and where it is covered by your signature.
- Unknown keys are ignored.
- A missing, malformed, or unsupported-version file means the app is simply
  not managed. Conductor never guesses.

### 2.3 What Conductor requires of the installed app

- Developer ID signed with a real Team ID, and notarized. **Unsigned and
  ad-hoc-signed apps are refused** — there is no Team ID to anchor trust
  to, and Conductor does not do trust-on-first-use.
- A non-empty `CFBundleIdentifier` and `CFBundleShortVersionString`.
- Installed in /Applications.

## 3. The manifest — the file on your server

### 3.1 Schema (format 1)

```json
{
  "conductor_manifest": 1,
  "bundle_id": "com.example.yourapp",
  "version": "2.4.1",
  "build": "241",
  "url": "https://cdn.example.com/YourApp-2.4.1.dmg",
  "sha256": "9f2a…",
  "urgency": "data_loss",
  "changelog_url": "https://example.com/changelog",
  "min_system_version": "13.0",
  "size": 19293798,
  "released": "2026-11-03",
  "notes": [
    {"type": "notice", "text": "Your library moves to a new format on first launch."},
    {"type": "removed", "text": "Import from iTunes Library XML."},
    {"type": "added", "text": "Pin any wave to the sidebar."},
    {"type": "fixed", "text": "AirPlay output resumes after the Mac wakes."}
  ],
  "history": [
    {"version": "2.4.0", "date": "2026-10-14", "notes": [
      {"type": "fixed", "text": "Scrubbing no longer skips the last second of a track."}
    ]}
  ]
}
```

| Key                  | Type   | Required | Meaning                                   |
|----------------------|--------|----------|-------------------------------------------|
| `conductor_manifest` | number | yes      | Format version. MUST be `1`.              |
| `bundle_id`          | string | yes      | MUST equal the managed app's `CFBundleIdentifier`. A mismatch is a hard refusal (not a reason to try the fallback). |
| `version`            | string | yes      | The advertised version, for display and for deciding whether to *start* an update. Advisory — see §3.2. |
| `url`                | string | yes      | Absolute HTTPS URL of the artifact (DMG or zip, §4). |
| `build`              | string | no       | Advertised `CFBundleVersion`, used as a tie-break when short versions are equal. |
| `sha256`             | string | no       | Lowercase hex SHA-256 of the artifact. If present, a mismatched download is discarded. This is a transport-integrity check, not a security boundary — the security boundary is the signature check (§5). |
| `urgency`            | string | no       | One of a closed vocabulary: `system_risk`, `data_loss`, `data_exfiltration`. See §8. Unknown tokens are ignored. |
| `changelog_url`      | string | no       | Shown to users alongside update and recall notices. |
| `min_system_version` | string | no       | Minimum macOS version for the advertised build. Advisory in format 1; Conductor MAY use it to withhold the update on older systems. |
| `size`               | number | no       | Size of the artifact in bytes, shown to users. Display only. |
| `released`           | string | no       | The advertised version's release date, `YYYY-MM-DD`. Display only — it never affects deferral (§8). |
| `notes`              | array  | no       | Release notes for the advertised version: typed plain-text items. See §3.5. |
| `history`            | array  | no       | Release notes for earlier versions, so a user who skipped some can read what they missed. See §3.5. |

Unknown keys are ignored.

### 3.2 The manifest is not trusted

This is the central design decision, and it cuts both ways:

- The manifest tells Conductor **where to look, never what to accept.**
  Everything security-relevant — bundle identity, version, signature, team,
  notarization — is verified from the signed artifact itself after
  download. You cannot weaken verification through the manifest, and
  neither can anyone who hijacks it.
- Because it is unauthenticated, the manifest also **cannot carry
  authority**: no install commands, no downgrade requests, no hooks. Fields
  like `urgency` are deliberately bounded so that a forged manifest's worst
  case is embarrassment, not compromise (§8).

### 3.3 Serving requirements

- Serve over HTTPS with status 200. Conductor fetches with caches disabled
  and a 30-second timeout; any transport failure or non-200 status counts
  as "unreachable" and triggers the fallback (§6).
- The manifest advertises exactly one version: the one you want users on.
  Updating that file when you release **is the entire server-side
  protocol.** (`history`, §3.5, describes earlier versions for reading
  only; nothing in it is installable.)
- Keep cache TTLs short — minutes, not days — especially on the fallback
  (§6.1, §7).

### 3.4 Version comparison

Dotted version strings compare component-wise: numerically where both
components are numeric (`1.9` < `1.10`), lexically otherwise; missing
components count as zero (`1.2` == `1.2.0`). If short versions are equal
and both sides carry a build number, builds break the tie the same way.

An update begins only when the advertised version is strictly newer than
the installed one — and the authoritative downgrade check happens again
later, against the downloaded bundle's own `Info.plist` (§5).

### 3.5 Release notes

Release notes live in the manifest as a list of **typed, plain-text
items**. You say what kind of change each one is; Conductor draws the
badge. Every app's notes therefore look the same, in the same order, and a
user who knows one knows where to look in all of them.

```json
"notes": [
  {"type": "removed", "text": "Import from iTunes Library XML. Use File › Import from Music instead."},
  {"type": "fixed",   "text": "AirPlay output resumes after the Mac wakes."}
]
```

**The vocabulary is closed.** Seven types, written by you:

| Key        | Badge    | Means                                                         |
|------------|----------|---------------------------------------------------------------|
| `notice`   | Notice   | Read this before updating: migrations, requirements, caveats. |
| `removed`  | Removed  | A feature is gone from this build.                            |
| `disabled` | Disabled | Still in the app, switched off for now.                       |
| `security` | Security | A vulnerability was closed.                                   |
| `added`    | Added    | New capability.                                               |
| `improved` | Improved | Existing behavior got better.                                 |
| `fixed`    | Fixed    | A bug is gone.                                                |

An eighth badge, **Retracted**, is generated by Conductor when an
advertised build disappears (§7). It is never accepted from a manifest.

**Render order is fixed** and is the order of the table above — what takes
something away comes first. Conductor groups items by type, one badge per
group; the order of items in your array only decides their order *within*
a group. Users choose which categories they see in full and which ones
hold an update for a deliberate install, so type your notes honestly: a
`removed` item filed as `improved` skips a warning your users asked for.

**Item rules:**

- `type` is one of the seven keys above, lowercase, exact. An item with
  any other `type` is **dropped, never guessed at**; Conductor logs it and
  tells the user that the update has a note it can't display (pointing at
  `changelog_url` if you supplied one). The same happens to an item typed
  `retracted`. The rest of the manifest is unaffected, so a manifest
  written for a newer vocabulary degrades safely on an older Conductor.
- `text` is **plain text**: no markup, no links, no emphasis. Whatever you
  write is shown literally. Whitespace, including newlines, collapses to
  single spaces. Text longer than 500 characters is truncated. An item
  with no text is dropped.
- Conductor reads at most 100 notes per version.

**History.** `notes` (with `released`) always describes the advertised
`version`. To let a user who skipped versions read what they missed, add
`history`: an array of `{ "version", "date", "notes" }` objects for
earlier versions, each `notes` following the rules above and `date` in
`YYYY-MM-DD` form.

- Conductor shows a history entry only when its version is **strictly
  newer than the installed version and strictly older than the advertised
  one**. Entries at or below what the user has are ignored, and so is an
  entry for the advertised version itself — top-level `notes` is the one
  place those live.
- Order doesn't matter; Conductor sorts newest first. If two entries name
  the same version, the first wins.
- Conductor reads at most the first 10 entries.

Release notes are **display data**. Like everything else in the manifest
(§3.2) they are unauthenticated and are never an input to verification:
what gets installed is decided by the signed artifact alone, and a
malformed `notes` or `history` block can never cause a manifest to be
refused. `changelog_url` remains the place for anything longer or richer.

## 4. Artifact requirements

- **Format:** a DMG or a zip, detected by content, not by file extension.
- **Layout:** exactly one `.app` bundle — at the root of the DMG, or at
  the root of the zip (one wrapping directory is tolerated). Anything else
  (background images, symlinks to /Applications) may be present; only the
  single `.app` is used. Zero or multiple `.app` bundles is an error.
- **The `.app` inside MUST:**
  - carry the same `CFBundleIdentifier` as the installed app;
  - carry a strictly newer version (§3.4) in its `Info.plist`;
  - be Developer ID signed by the **same Team ID** as the installed app;
  - be notarized, with the ticket **stapled**. Conductor assesses the
    staged bundle with Gatekeeper machinery; stapling makes that
    assessment reliable offline and is the same courtesy you owe manual
    downloaders.

The artifact SHOULD be the same file you offer for manual download. That is
the whole philosophy: your app must already survive a user dragging a new
version over the old one, and Conductor automates exactly that contract —
nothing more.

## 5. What Conductor verifies (the guarantees)

The update pipeline is: fetch → download → extract to staging → **verify**
→ wait for quit → atomic swap → dequarantine. The staging directory lives
on the same volume as /Applications, so the swap is atomic by
construction. Two properties hold at every step:

> **1. Any failure, at any stage, leaves the installed app untouched.**
> **2. The swap is the sole mutation of /Applications in the entire flow.**

All checks run against the **staged, downloaded** bundle, in order:

1. **Bundle identity.** Staged `CFBundleIdentifier` MUST equal the
   installed one. Hard fail otherwise — user expectations and macOS
   privacy (TCC) grants are keyed to it.
2. **Downgrade refusal.** The staged bundle's version, read from its own
   `Info.plist`, MUST be strictly newer than the installed one. This
   closes the replay attack — a hijacked URL serving an older, validly
   signed, vulnerable build — and it is unconditional: there is no
   downgrade path, not even for recalls (§7).
3. **Signature and Team ID pinning.** The staged bundle MUST pass strict
   static code validation against the requirement:

   ```
   anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"
   ```

   where `<TEAMID>` was captured from the *installed* copy before anything
   was downloaded. All architectures are checked; validation is strict.
4. **Notarization.** The staged bundle MUST pass a Gatekeeper execute
   assessment (Apple's ticket exists for exactly this bundle).

Only after all four pass does Conductor proceed: it strips
`com.apple.quarantine` from the verified staged bundle (Conductor has
already run a *stricter* check than Gatekeeper would — Gatekeeper does not
pin Team IDs across versions), waits for the app to not be running (asking
the user to quit, or updating on quit — **never force-terminating**),
performs the atomic swap, and moves the displaced old bundle to the Trash,
user-recoverable.

Consequences you get for free:

- **TCC grants survive every update.** macOS keys them on bundle ID plus
  signing identity, and checks 1 and 3 guarantee both are unchanged. There
  is nothing to re-prompt and nothing for you to do.
- **No first-launch quarantine dialog, no App Translocation** for updates
  Conductor installs.
- **A failed or interrupted update is a non-event.** Staging is discarded;
  the installed app never changed.

## 6. Fallback semantics

`fallback_url` exists because single-provider hosting goes down. If your
primary manifest is on infrastructure that stumbles, an updater that goes
dark with it isn't doing its job. Point the fallback at a genuinely
separate failure domain — different host, different CDN.

Two rules keep it honest:

- **Unreachability only, never a second opinion.** The fallback is
  consulted when the primary transport fails (connection error, timeout,
  non-200). If the primary responds, its manifest wins, always — even if
  the response is malformed, refuses to parse, or names the wrong bundle
  ID. Those are errors to surface, not reasons to shop for a better
  answer.
- **Same verification regardless of source.** Which URL served the
  manifest never changes what is installable. Every artifact passes §5 in
  full.

### 6.1 Cache staleness

A CDN-cached fallback manifest can keep advertising a build you have since
recalled. Conductor mitigates this by preferring the primary whenever it is
reachable, but you SHOULD keep fallback cache TTLs short so a recall
propagates everywhere quickly.

## 7. Recalls: re-point, never downgrade

To recall a bad build, **point your manifest back at the previous
version** — same mechanism as a release, in reverse. What happens next
depends on what users saw:

- **Notified but not yet installed** (the common case): Conductor clears
  the pending update and tells the user plainly — *"the developer
  retracted update X; you already have the latest build"* — with your
  `vendor_url`/changelog for the curious. Loud on purpose: a silently
  vanishing update badge reads as a bug in exactly the tool whose product
  is trust.
- **Already installed the recalled build:** Conductor informs the user and
  points them at you, and **never downgrades automatically**. The notice
  persists quietly until your manifest advertises a version ≥ the
  installed one.
- **Never surfaced** (the user's deferral window hid it, §8): dropped
  silently. No promise was made, so no correction is owed.

Why no automatic downgrade, even for a legitimate recall: the manifest is
unauthenticated, so a "please downgrade" signal in it is indistinguishable
from a replay attack — the exact attack the downgrade check exists to
stop. Recalls therefore route through the human. **Your remedy for a bad
build is shipping a fixed newer version** — which is also what you would
tell manual-download users, so the two channels stay consistent.

Conductor also re-fetches the manifest immediately before starting any
install the user accepted earlier, so a recall issued between notification
and click is honored.

## 8. Deferral and the urgency vocabulary

Users may configure Conductor to hold newly observed versions back for a
fixed window (off, one day, or one week — their choice, global, not
yours) before being told about them. The clock starts when *their*
Conductor first observes the version, not from any date you publish — a
manifest date could be backdated to defeat the window. Expect adoption of
a release to ramp over about a week, exactly as it would with manual
downloads; a version you recall during its window quietly never existed
for most users.

A manifest MAY carry an `urgency` token when a release fixes something
genuinely dangerous. Its only effect is to **skip the deferral window** —
notify users now. It changes nothing else: verification (§5), the
pre-install recall re-check (§7), and the user's consent to install are
all unconditional.

The vocabulary is closed, and deliberately contains no mild option:

| Token               | Conductor's rendered copy (fixed)                            |
|---------------------|--------------------------------------------------------------|
| `system_risk`       | The developer has flagged this update as fixing a vulnerability that puts the system at risk. |
| `data_loss`         | The developer has flagged this update as fixing a bug that can cause data loss. |
| `data_exfiltration` | The developer has flagged this update as fixing a potential data exfiltration issue. |

You cannot write the alert text; Conductor renders its own fixed copy per
token, attributed to you. The only words available are admissions about
your own software, so invoking the flag is reputationally expensive unless
it is true — the vocabulary polices itself. Unknown tokens are ignored (so
a future addition to this table degrades safely on older Conductors), and
the token is honored only on the currently advertised version.

## 9. Testing your integration

```
Conductor.app/Contents/MacOS/Conductor --dev-mode com.example.yourapp
```

Developer mode shows only your app and permits plain-HTTP URLs **for that
bundle ID only**, so you can exercise the full notify → verify → swap flow
against a local server (`python3 -m http.server`) before anything is
public. Transport is the *only* thing relaxed: signature validation, Team
ID pinning, notarization, and downgrade refusal run exactly as in
production — your test artifact must be the same signed, notarized bundle
your release pipeline will ship. Dev mode is per-session, visibly
indicated, and never remembered.

A minimal integration test:

1. Build and notarize versions N and N+1 of your app, both containing
   `conductor.json` pointing at `http://localhost:8000/manifest.json`.
2. Install version N in /Applications; serve N+1's artifact and a manifest
   advertising it.
3. Run Conductor in dev mode; accept the update; confirm the swap and that
   your app's settings, state, and TCC permissions survived.
4. Re-point the manifest back at N and confirm the recall notice appears
   (and that nothing downgrades).

## 10. What Conductor will never do

These are refusals, not roadmap gaps. They are what the one-sentence
security claim costs, and they are permanent.

**No vendor post-install hooks — ever.** `conductor.json` and the manifest
will never support a script, an executable path, or a "run after update"
field, for three reasons:

1. **A hook would nullify the security model.** Team ID pinning proves the
   *bundle* is yours. A hook field in a JSON file fetched over the network
   is unsigned instruction-following — exactly the hole the rest of this
   design exists to close.
2. **Your app already handles its own migrations on launch**, because
   users also update by dragging a DMG. An app that needs an install hook
   is broken for manual updates too.
3. **Auditability is the product.** "Conductor can only ever swap one
   signed bundle for a newer signed bundle from the same vendor" is a
   one-sentence security claim. Every feature that complicates that
   sentence costs trust.

And the rest:

- **No automatic downgrades**, including for recalls (§7).
- **No patching inside bundles.** Whole-bundle replacement only; modifying
  a signed bundle's contents breaks its seal.
- **No managing unsigned or ad-hoc-signed apps.**
- **No force-quitting** a running app to update it.
- **No privileged install steps.** Apps needing kexts, system extensions,
  or privileged helpers are installer-package territory, and out of scope
  by design.

If your release process is "notarize a bundle, upload it, update one JSON
file," Conductor fits. If it needs more than that, Conductor is the wrong
tool, on purpose.
