---
title: Conductor — Bundle Replacement Flow
status: Draft (design, pre-implementation)
created: 2026-07-19
updated: 2026-07-19
tags: [conductor, security, replacement, spec]
related: [MUW-145]
---

# Bundle Replacement Flow

How Conductor replaces a third-party app bundle: **verify → stage → quit →
swap → dequarantine → finish**. The security rationale is written down here
so it survives into the public spec's security section later.

Design invariants:

*	**The installed app is never touched until the new bundle is fully
	verified.** Any failure at any step leaves /Applications exactly as
	it was.
*	**No vendor post-install hooks. Ever.** See rationale at the bottom.
*	**Whole-bundle replacement only.** Patching files inside a signed
	bundle invalidates the signature (same conclusion as MUW-145).
*	**Conductor never updates itself through this flow.** Self-update is
	a different, harder problem (sized L, deliberately descoped).
	Conductor may *notify* about its own updates only.

---

## 0. Inputs

*	Installed app at `/Applications/<Name>.app`
*	Its `conductor.json` (update URL, fallback URL, vendor URL)
*	The manifest fetched from the update URL (latest version, artifact
	download URL)

Before downloading anything, capture from the **installed** copy:

*	Bundle identifier (`CFBundleIdentifier`)
*	Installed version (`CFBundleShortVersionString` / `CFBundleVersion`
	from Info.plist — conductor.json does not carry a version, by design)
*	**Team ID**, via `SecStaticCodeCreateWithPath` +
	`SecCodeCopySigningInformation` (`kSecCSSigningInformation`), reading
	`kSecCodeInfoTeamIdentifier`

The installed copy's Team ID is the trust anchor for everything below.

Edge case to decide during implementation: installed app is unsigned or
ad-hoc signed (no Team ID). Options: refuse to manage it, or first-run
"trust on first update" pinning. Leaning **refuse** — signed + notarized
apps only. Simpler story, and it's 2026.

## 1. Download

*	`NSURLSession` download of the artifact to a temp location.
*	The artifact **will** carry `com.apple.quarantine`. That is expected
	and fine — quarantine is only stripped after *our* verification passes
	(step 3), never before.
*	Update URL unresponsive → try fallback URL. Both dead → surface the
	vendor URL to the user and stop.
*	HTTPS only for update, fallback, and artifact URLs. No exceptions in
	the spec. (Sole runtime exception: single-app `--dev-mode`, see
	dev-mode.md.)

## 2. Extract to staging (same volume!)

*	Staging directory must live on the **same APFS volume** as the
	destination, or the atomic rename in step 5 silently becomes a
	non-atomic copy. `NSTemporaryDirectory()` is not guaranteed to
	qualify — create staging alongside the target instead, e.g.
	`/Applications/.conductor-staging/<bundle-id>/`.
	(Note: `/Applications` lives on the Data volume via firmlink, same as
	user space, so this is one volume in practice — but do not rely on
	that; create staging next to the destination and it is true by
	construction.)
*	DMG artifact: attach with `hdiutil attach -nobrowse -readonly`, copy
	the .app out, detach. ZIP: extract. (Artifact format decision — DMG
	vs zip — still open; DMG is what release.py already produces.)

## 3. Verify (the whole ballgame)

All checks run against the **staged** bundle. In order:

1.	**Bundle ID match.** Staged `CFBundleIdentifier` == installed. A
	mismatched bundle ID is a hard fail, not a warning — TCC grants and
	user expectations are keyed to it.
2.	**Version sanity.** Staged version > installed version. Refuse
	downgrades (a hijacked manifest serving an old, vulnerable-but-validly-
	signed build is a real attack — this check is load-bearing, not
	cosmetic).
3.	**Signature validity.** `SecStaticCodeCreateWithPath` on the staged
	bundle, then `SecStaticCodeCheckValidity` with a requirement string
	pinning the Team ID captured in step 0:

	```
	anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"
	```

	Use `kSecCSCheckAllArchitectures | kSecCSStrictValidate`. Decide at
	implementation whether to pay for `kSecCSCheckNestedCode` (slow on
	big bundles; strict validation of the outer seal already covers the
	resource envelope).
4.	**Notarization.** Practical route: shell out to
	`spctl --assess --type execute` on the staged bundle (the supported
	SecAssessment APIs are awkward from third-party code; spctl is the
	honest tool). This confirms Apple's ticket exists for exactly this
	bundle.

Any failure → delete staging, log, notify user, done. The installed app
was never touched.

### Why Team ID pinning is the scheme (rationale for the spec)

Sparkle ships EdDSA signing because it predates ubiquitous notarization:
vendors generate keys, embed public keys in the app, sign appcasts, and
key management is on them. Conductor instead reuses Apple's PKI, which
every managed app already participates in:

*	A **hijacked update/fallback URL** yields nothing: the attacker's
	payload fails the Team ID requirement unless they also hold the
	vendor's Developer ID signing identity — at which point the update
	channel is not the weak link.
*	A **compromised CDN** is the same case.
*	**Key management cost for vendors: zero.** They already sign and
	notarize to ship on macOS at all. Adopting Conductor adds one static
	JSON file and no cryptographic ceremony.
*	The **downgrade check** (3.2 above) closes the remaining gap:
	replay of an older validly-signed build.

## 4. Quit check

*	`+[NSRunningApplication runningApplicationsWithBundleIdentifier:]`.
*	If running: prompt the user — "Quit & Update" / "Update on quit" /
	"Skip". Never force-terminate. Swapping under a running app mostly
	works (open files survive by inode) but the running instance can
	fault later on lazily-loaded resources; not worth it.
*	"Update on quit": observe termination via NSWorkspace notifications,
	then proceed to step 5.

## 5. Atomic swap

*	`-[NSFileManager replaceItemAtURL:withItemAtURL:...
	options:usingNewMetadataOnly resultingItemURL:error:]` — atomic on
	same volume, and handles the old-item preservation dance.
	(Alternative: `renamex_np` with `RENAME_SWAP` for full control.)
*	Keep the displaced old bundle in staging until post-swap checks pass,
	then move it to the **Trash** (`NSWorkspace recycleURLs`), not
	`unlink` — user-recoverable if anything smells wrong.
*	Ownership/permissions failure (EPERM — app owned by root/another
	admin): v1 answer is to fail with a clear message. A privileged
	helper (`SMAppService` daemon) is the v2 answer if it proves common;
	do not build it speculatively — it drags in XPC and a second signed
	binary.

## 6. Dequarantine

*	Strip `com.apple.quarantine` **recursively** from the swapped-in
	bundle (`removexattr` walk). We have already run a *stricter* check
	than Gatekeeper would (Gatekeeper does not pin Team IDs across
	versions; we do), so first-launch prompts and App Translocation are
	pure downside at this point.
*	Sequencing note: stripping on the staged bundle pre-swap also works;
	post-swap keeps the rule simple ("what lands in /Applications gets
	dequarantined last"). Either way it happens **only after step 3
	passed in full**.
*	`com.apple.provenance` (macOS 14+) will remain — it cannot be
	removed and does not need to be.

## 7. Finish

*	Optional cosmetics: LaunchServices notices the change via fsevents on
	its own; if a stale Dock/Finder icon is ever observed, `touch` the
	bundle or `lsregister -f` it. Do not do this routinely.
*	**TCC grants survive automatically** — they key on bundle ID +
	signing identity, and steps 3.1/3.3 guarantee both are unchanged.
	Nothing to do; worth stating so nobody "fixes" it.
*	Offer relaunch (`-[NSWorkspace openApplicationAtURL:...]`) if the app
	was quit in step 4.
*	Clean staging.

---

## No vendor hooks — rationale (goes in the public spec verbatim-ish)

conductor.json will never support a post-install script, executable hook,
or "run after update" field. Reasons:

1.	**It would nullify the security model.** Team ID pinning proves the
	*bundle* is the vendor's. A hook field in a JSON file fetched over
	the network is unsigned instruction-following — exactly the hole the
	rest of this design exists to close.
2.	**Apps already handle their own migrations on launch**, because
	users also update by dragging DMGs. Any app that needs an install
	hook is broken for manual updates too.
3.	**Auditability is the product.** "Conductor can only ever swap one
	signed bundle for a newer signed bundle from the same vendor" is a
	one-sentence security claim. Every feature that complicates that
	sentence costs trust.

Apps needing genuine privileged install steps (kexts, system extensions,
PrivilegedHelperTools) are out of scope: that is installer-package
territory, and Conductor should say so in the spec rather than grow
toward it.

## Open questions

*	Unsigned/ad-hoc installed apps: refuse, or trust-on-first-update?
	(Leaning refuse — see step 0.)
*	Artifact format in the spec: DMG only, zip only, or both?
*	Notarization check: live with shelling out to `spctl` long-term?
*	Manifest schema for the *universal* spec: muwav's existing
	`latest.json` (`advertise` / `latest` / `minimum` / `dangerous`,
	integer builds) has no download URL and no semver. The universal
	manifest needs at minimum `version` + `url`; decide how much of the
	muwav schema generalizes vs stays muwav-specific.
