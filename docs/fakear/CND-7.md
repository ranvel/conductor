---
key: CND-7
summary: Network gate — entitlement diff of the staged bundle, Internet Access Policy, inspect phase, approval sheets
status: DAT
resolution:
priority: High
fixVersion:
created: 2026-11-05
updated: 2026-11-05
session:
tags: [v2, network-isolation, entitlements, internet-access-policy, engine]
related: [CND-3, CND-4, CND-6]
---

# CND-7 — Network gate

## Context
	Read `docs/conductor-v2.md` and `docs/readme-network-isolation.md`
	first. Specs: the NETWORK row in `ref-assets/Main window`, the
	"Inspecting the new build" pane in `ref-assets/Empty & edge states`,
	and the two "Gains internet access" sheets in `ref-assets/Interrupt
	sheets`.

	This is the ticket that makes Conductor's thesis visible. For every
	managed app the detail pane shows one of three network states, read
	from the *installed* bundle:
	- No network access — sandboxed, no `com.apple.security.network.client`
	  and no `.network.server` entitlement.
	- Has access, with policy — the bundle ships
	  `Contents/Resources/InternetAccessPolicy.plist` (Objective
	  Development's Internet Access Policy format, the one Little Snitch
	  reads); the row expands to the policy's connections and purposes.
	- Has access, no policy.
	A non-sandboxed app has unrestricted network and counts as "has
	access" (only fully sandboxed apps can drop network entitlements).

	When a new build crosses from "no access" to "has access", and the
	user's resolved preferences (CND-4) say approval is required, the
	update needs consent before install — with the entitlement diff shown,
	and the policy rendered inline when there is one so the user approves
	something concrete. If "…unless it ships an Internet Access Policy" is
	on and the new build has one, no consent is needed, but the row still
	shows the change.

	Because this reads the *downloaded* bundle, the pipeline needs an
	inspect step before the user is asked: download → verify → inspect →
	ask. The design shows "Downloading to inspect… / Verify Team ID /
	Compare entitlements with 0.8 / Ready to decide". That means
	Conductor pre-fetches and fully verifies the artifact when the gate is
	on, and parks with a decision pending — a new pause point in
	`CDRUpdateOperation`, cousin of the existing update-on-quit parking.

	Invariants (CLAUDE.md) — this is the ticket most able to break them:
	- Inspect runs AFTER Verify, on the staged bundle, never before.
	  Entitlements and the policy plist are read with the same
	  Security.framework path as the Team ID check, not by trusting file
	  contents on disk alone where a sealed source exists.
	- Inspect is a consent input, not a verification input. A build that
	  passes Verify is installable; the gate only decides whether to ask.
	- No extra mutation of /Applications, no staging move, no quarantine
	  change. A declined approval discards staging like any other failure.

## Recon
	Cici — where an answer forks, give lettered options with a recommendation.
	1. Reading entitlements: confirm `SecCodeCopySigningInformation` with
	   `kSecCSRequirementInformation` yields `kSecCodeInfoEntitlementsDict`
	   on the staged bundle; identify the three keys that matter
	   (`com.apple.security.app-sandbox`, `.network.client`,
	   `.network.server`) and define `CDRNetworkPosture` {none, client,
	   server, both, unrestricted(non-sandboxed)}. Add it to
	   `CDRCodeSignature` or a sibling `CDREntitlementInspector`;
	   recommend the sibling so `CDRCodeSignature` stays the security
	   perimeter and nothing else. Same reader for installed and staged.
	2. Internet Access Policy: fetch and read Objective Development's
	   published format for `InternetAccessPolicy.plist` (keys, connection
	   entries, purpose strings, deny entries, localization). Write a
	   parser `CDRInternetAccessPolicy` that produces rows of (remote
	   pattern or "Any …" wording, purpose). Decide how much of the format
	   to honor in v1 of this feature — recommend: connections with hosts/
	   domains + purpose; ignore the rest with a log line. Decide where it
	   is read from: `Contents/Resources/` of the staged bundle, which is
	   under the code seal already verified in Verify.
	3. Pipeline: map `CDRUpdateOperation`'s phase machine and the existing
	   park (update-on-quit). Fork for where the gate's pause lives:
	   (a) a new `Inspect` phase after `Verify` with a `parkedForApproval`
	       state the controller resumes or cancels;
	   (b) the controller runs the operation to the end of Verify, reads
	       the posture itself, and starts a second operation on consent.
	   Recommend (a) — one operation owns staging and cleanup.
	   Define what happens on quit/relaunch with an approval parked
	   (recommend: discard staging; the row goes back to Available and
	   re-inspects on the next click — nothing persists).
	4. Trigger: when does inspection start? Fork: (a) automatically when an
	   update becomes Available and the gate is on, so the row can show
	   "Approve network access" without a click; (b) on the first install
	   click. Recommend (a) for the NEEDS YOU section to be truthful, with
	   a bandwidth note in Settings copy; deferred/held/stopped updates do
	   not pre-fetch.
	5. Gate logic as a pure function: (installed posture, staged posture,
	   policy present?, resolved preferences) → {noAsk, askWithPolicy,
	   askWithoutPolicy}. Table it in tests, including server-only
	   additions and the non-sandboxed → sandboxed-no-network direction
	   (that one is good news: show it, never ask).
	6. UI: fill the NETWORK row (CND-3) for all three states with the
	   policy expansion; the Inspecting pane's step list driven by phase;
	   the two sheets via CND-6's `presentNetworkApproval…` with Approve
	   default when a policy exists and Skip default when none. Skip this
	   version marks the version as skipped the same way an explicit skip
	   does today (confirm how, or add it — recommend reuse of the ignore
	   list's per-version memory if one exists, else a `skippedVersion` on
	   `CDRAppUpdateState`).
	7. Developer interest scheme (CND-4): when `exposesDeveloperDetail` is
	   on, the NETWORK row also shows the raw entitlement keys and Team ID.
	8. Harness: extend `TestHarness/build-testee.sh` to produce a v1.2
	   testee that adds `network.client` with a policy plist and a v1.3
	   that adds it without one, so `CDRUpdateOperationIntegrationTests`
	   exercises both branches.
	9. Propose the fix file by file with tests: the posture reader (against
	   the built Conductor.app, like `CDRCodeSignatureTests`), the policy
	   parser (fixture plists), the gate function, the phase-machine park/
	   resume/cancel, and the integration branches.
	Write findings to `attach/CND-7/` and flip the status.

## Out of scope
	- Any change to what Verify accepts. If inspection ever wants to
	  refuse a build, that is a new ticket and a spec conversation.
	- Live traffic observation, firewall integration, or talking to Little
	  Snitch — Conductor only reads what the bundle declares.
	- Self-update.

## DAT (r)
	- [ ] The NETWORK row shows "No network access" for a sandboxed app without network entitlements, "with policy" (expandable, correct rows) for one that ships a policy, and "no policy" otherwise; a non-sandboxed app shows as having access.
	- [ ] A build that adds `network.client` with a policy, gate on, exemption on: installs without a sheet; the row shows the change.
	- [ ] Same build, exemption off: the "ships a policy" sheet appears with the diff and the policy table; Approve is default; Approve installs, Skip discards staging and marks the version skipped.
	- [ ] A build that adds `network.client` with no policy: the "no policy" sheet appears, Skip is default, the amber strip is shown.
	- [ ] A build going from non-sandboxed to sandboxed-no-network never asks and the row celebrates it.
	- [ ] While inspecting, the pane shows the step list advancing; quitting Conductor mid-inspect leaves /Applications untouched and no staging behind.
	- [ ] Inspect never runs on a build that failed Verify (assert in the integration test with the ad-hoc-signed artifact).
	- [ ] `CDRCodeSignature` is unchanged except for any shared helper; `kCDRValidationFlags` untouched.

## Recon outcome (Cici, 2026-11-05)
	Implemented in one Fable-Protocol pass; findings, every resolved fork and
	a DAT-line → test table are in `attach/CND-7/recon.md`.

	The verification path is unchanged: no diff in `CDRCodeSignature`, the
	swapper, notarization, quarantine, staging, download or dev-mode code,
	and `kCDRValidationFlags` is untouched. Inspect is a new phase that
	runs only after the whole of Verify and only reads.

	Two corrections to this ticket's premises:
	- Recon 1: `kSecCodeInfoEntitlementsDict` needs no
	  `kSecCSRequirementInformation`; it comes back with the signing-
	  information call already in use.
	- Recon 2: Objective Development's published format could not be
	  fetched (their help site renders only in a browser). The parser is
	  written against 21 real policy files found in /Applications.

	Calls I made that r should look at in DAT:
	- Look-ahead download happens only for apps whose installed build has
	  no (or unreadable) network access — narrower than Recon 4 option (a).
	  It never installs without a click, even when nothing needs asking.
	- "Skip this version" is a new policy outcome and row state; a skipped
	  row sits under UPDATES and comes back on a per-app Check now.
	- Unreadable entitlements are "Unknown" and err toward asking.
	- A look-ahead that fails is logged, not notified.
	- Staging is now also removed when Conductor quits.

	Not checked: the manual GUI pass, a real look-ahead through the
	controller, and the quit path — r's own debug Conductor was running, so
	I did not launch a second instance or put a test app in /Applications.

