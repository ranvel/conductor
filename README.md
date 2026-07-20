# Conductor

**One updater for your Mac apps. No framework, no keys, no ceremony.**

Conductor is a standalone macOS app that keeps other apps up to date. If you
ship a signed, notarized Mac app outside the App Store, adopting Conductor
costs you one JSON file inside your bundle and one JSON file on your server.
That's the whole integration.

> **Status: pre-release.** The replacement engine is built and tested; the
> product UI and background scanning are in progress. See
> [docs/roadmap.md](docs/roadmap.md). Nothing below is final until v1.0.

## Why another updater?

Sparkle is excellent, but it predates ubiquitous notarization. It asks you to
embed a framework, generate an EdDSA key pair, guard the private key forever,
and sign every appcast. Lose the key and your update channel is dead; leak it
and your users are someone else's.

Conductor's bet: **Apple's PKI already solved this.** Every app it manages is
already Developer ID-signed and notarized — you did the cryptographic work
when you shipped. Conductor pins your Team ID and lets Apple's infrastructure
do the rest.

The security claim fits in one sentence:

> *Conductor can only ever swap one signed bundle for a newer signed bundle
> from the same vendor.*

Concretely:

- A **hijacked update URL or compromised CDN** yields nothing — the attacker's
  payload fails the pinned Team ID check unless they also hold your Developer
  ID signing identity, at which point your update channel was not the weak link.
- A **replayed old build** (validly signed, known-vulnerable) is refused — the
  version check reads the downloaded bundle's own Info.plist, never the
  manifest's claims.
- **Your users' TCC grants survive** every update: bundle ID and signing
  identity are verified unchanged, which is exactly what TCC keys on.

## Adopting Conductor

### 1. Put `conductor.json` in your bundle

At `Contents/Resources/conductor.json`, **before you sign**:

```json
{
  "conductor": 1,
  "update_url": "https://example.com/updates/manifest.json",
  "fallback_url": "https://cdn.example.com/updates/manifest.json",
  "vendor_url": "https://example.com"
}
```

Because it lives under your code seal, a tampered `conductor.json` breaks the
signature the next update is verified against. The `fallback_url` is consulted
only when the primary is unreachable — never as a second opinion — so mind
your CDN cache TTLs. There is no version field here: your version lives in
Info.plist, where it always did.

### 2. Host a manifest

At your `update_url`:

```json
{
  "conductor_manifest": 1,
  "bundle_id": "com.example.yourapp",
  "version": "2.4.1",
  "build": "241",
  "url": "https://cdn.example.com/YourApp-2.4.1.dmg",
  "sha256": "…",
  "changelog_url": "https://example.com/changelog",
  "min_system_version": "13.0"
}
```

Required: `conductor_manifest`, `bundle_id`, `version`, `url`. The artifact is
a DMG or zip containing your `.app` — the same one you'd offer for manual
download. Update the manifest when you release; that's the entire server-side
protocol. To recall a bad build, point the manifest back at the previous
version — Conductor tells affected users loudly and never downgrades anyone
silently (ship a fixed build to move them forward).

### 3. There is no step 3

No SDK, no framework, no code changes, no keys to manage. Your app must
already survive a user dragging a new version over the old one — that's the
same contract Conductor automates.

## The rules (read before adopting)

Conductor is deliberately strict. These are features:

- **Signed + notarized apps only.** Unsigned or ad-hoc-signed apps are refused
  — there is no Team ID to anchor trust to.
- **Versions only go up.** Downgrades are refused unconditionally, even for
  legitimate recalls (an unauthenticated "please downgrade" signal is
  indistinguishable from a replay attack).
- **No post-install hooks. Ever.** A hook field in a network-fetched JSON file
  would be unsigned instruction-following — the exact hole the rest of the
  design closes. Run migrations on launch, like you already do for
  drag-and-drop updates.
- **Whole-bundle replacement only.** Patching inside a signed bundle breaks
  the seal.
- **The manifest is not trusted.** It tells Conductor *where* to look, never
  *what* to accept. Everything security-relevant is verified from the signed
  artifact itself.

Apps needing privileged install steps (kexts, system extensions, privileged
helpers) are out of scope — that's installer-package territory.

## Why `fallback_url`?

Many vendors host their manifests and artifacts on GitHub (Releases or Pages).
That's a fine primary — but GitHub has proven noticeably less reliable in
recent months, and an updater that goes dark whenever one provider stumbles
isn't doing its job. `fallback_url` lets you point at a second server,
ideally on separate infrastructure (different host, different CDN, different
failure domain), so an outage at your primary doesn't strand your users.

Two rules keep the fallback honest:

- **The fallback is for unreachability only.** Conductor tries it solely when
  the primary URL is unresponsive — never as a second opinion. If the primary
  is reachable, its manifest wins, always.
- **Mind your cache TTLs.** A stale, CDN-cached fallback manifest can keep
  advertising a build you've since retracted. Keep fallback caching short so
  a recall propagates everywhere.

The fallback never changes what gets installed — every artifact passes the
same verification (Team ID pinning, notarization) regardless of which URL
served it.


## Testing your integration

```
conductor --dev-mode com.example.yourapp
```

Dev mode shows only your app and permits plain-HTTP URLs for it, so you can
exercise the full notify → verify → swap flow against
`python3 -m http.server`. Transport is the *only* thing relaxed: signature,
Team ID pinning, notarization, and downgrade refusal all run exactly as in
production — your test artifact must be the same signed, notarized bundle
your release pipeline will ship. It's session-only and never remembered.

## Building

Open `Conductor.xcodeproj` (Xcode 16+, macOS 15.6+) and build. Run the tests
with the ConductorTests scheme; the integration tests need the e2e artifacts
from `TestHarness/build-testee.sh` and skip when absent.

Design documents live in [docs/](docs/) — [replace-flow.md](docs/replace-flow.md)
is the security core and the right place to start a review.
