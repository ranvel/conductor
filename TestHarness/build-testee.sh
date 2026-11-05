#!/bin/zsh
#
# build-testee.sh — builds, signs, and packages ConductorTestee for
# Conductor's end-to-end dev-mode harness (see docs/replace-flow.md and
# docs/dev-mode.md).
#
# Builds (all Developer ID signed, hardened runtime):
#   1.0  sandboxed, no network entitlement   — the starting install
#   1.1  sandboxed, no network entitlement   — the ordinary update
#   1.2  sandboxed + network.client, ships an Internet Access Policy
#   1.3  sandboxed + network.client, ships no policy
#   0.9  NOT sandboxed                       — a starting install whose
#        update to 1.1 *drops* network access (never asked about)
#
# Output (in TestHarness/serve/):
#   ConductorTestee-1.0.app/   — install this into a target dir to start
#   ConductorTestee-0.9.app/   — the unsandboxed starting install
#   ConductorTestee-1.1.dmg    — the update artifact Conductor downloads
#   ConductorTestee-1.1.zip    — same payload as zip (zip-path testing)
#   ConductorTestee-1.2.dmg, ConductorTestee-1.3.dmg — the network-gate updates
#   manifest.json              — the Conductor manifest advertising 1.1, with
#                                typed release notes + history (spec.md §3.5)
#   manifest-1.2.json, manifest-1.3.json — advertise the network-gate updates
#
# Usage:
#   ./build-testee.sh [--notarize] [--port 8000]
#
# --notarize submits the artifacts via `xcrun notarytool` using the keychain
# profile in $NOTARY_PROFILE (default AC_NOTARY — same as muwav's 02-sign.sh)
# and staples the app. Without it, artifacts are Developer ID-signed but NOT
# notarized: Conductor's pipeline will then refuse them at the notarization
# step, which is itself a useful negative test.
#
set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="${IDENTITY:-Developer ID Application: Cedar Syntax LLC (F252L9GUBW)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
PORT=8000
NOTARIZE=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--notarize) NOTARIZE=1; shift ;;
		--port) PORT="$2"; shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

BUILD=build
SERVE=serve
rm -rf "$BUILD" "$SERVE"
mkdir -p "$BUILD" "$SERVE"

# Entitlements for the three postures the network gate (CND-7) tells apart.
# "none" signs with no entitlements at all: not sandboxed.
write_entitlements() { # $1=kind (sandbox | sandbox-client)  $2=output file
	local client=""
	[[ "$1" == "sandbox-client" ]] && client=$'\t<key>com.apple.security.network.client</key><true/>\n'
	cat > "$2" <<-PLIST
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>com.apple.security.app-sandbox</key><true/>
	${client}</dict>
	</plist>
	PLIST
}

# The Internet Access Policy the 1.2 build ships (Objective Development's
# format, the file Little Snitch reads). One literal purpose and one that is
# a key into the .strings table, the two styles real apps use; a connection
# with no host (must be dropped) and a Services entry (read, not shown).
write_policy() { # $1=app bundle
	cat > "$1/Contents/Resources/InternetAccessPolicy.plist" <<-PLIST
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>ApplicationDescription</key><string>IAP_APP_DESC</string>
		<key>DeveloperName</key><string>Cedar Syntax LLC</string>
		<key>Connections</key>
		<array>
			<dict>
				<key>IsIncoming</key><false/>
				<key>Host</key><string>*</string>
				<key>NetworkProtocol</key><string>TCP</string>
				<key>Port</key><string>80, 443</string>
				<key>Purpose</key><string>Checks the feeds you add for new episodes and downloads them.</string>
				<key>DenyConsequences</key><string>Feeds stop refreshing.</string>
			</dict>
			<dict>
				<key>IsIncoming</key><false/>
				<key>Host</key><string>search.example.com</string>
				<key>NetworkProtocol</key><string>TCP</string>
				<key>Port</key><string>443</string>
				<key>Relevance</key><string>Default</string>
				<key>Purpose</key><string>IAP_SEARCH_PURPOSE</string>
				<key>DenyConsequences</key><string>IAP_SEARCH_DENY</string>
			</dict>
			<dict>
				<key>Purpose</key><string>An entry that names no host.</string>
			</dict>
		</array>
		<key>Services</key>
		<array>
			<dict>
				<key>Identifier</key><string>com.apple.MapKit</string>
				<key>Purpose</key><string>Not shown by Conductor in this version.</string>
			</dict>
		</array>
	</dict>
	</plist>
	PLIST
	mkdir -p "$1/Contents/Resources/en.lproj"
	cat > "$1/Contents/Resources/en.lproj/InternetAccessPolicy.strings" <<-STRINGS
	"IAP_APP_DESC" = "A test app for Conductor's network gate.";
	"IAP_SEARCH_PURPOSE" = "Podcast directory search, only when you type in Search.";
	"IAP_SEARCH_DENY" = "Search returns nothing.";
	STRINGS
}

build_app() { # $1=short version  $2=build number  $3=output dir  $4=posture (sandbox | sandbox-client | none)  $5="policy" to ship one
	local version="$1" buildnum="$2" outdir="$3" posture="${4:-sandbox}" policy="${5:-}"
	local app="$outdir/ConductorTestee.app"
	mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

	cat > "$app/Contents/Info.plist" <<-PLIST
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>CFBundleIdentifier</key><string>com.ranvel.conductor-testee</string>
		<key>CFBundleName</key><string>ConductorTestee</string>
		<key>CFBundleExecutable</key><string>ConductorTestee</string>
		<key>CFBundlePackageType</key><string>APPL</string>
		<key>CFBundleShortVersionString</key><string>${version}</string>
		<key>CFBundleVersion</key><string>${buildnum}</string>
		<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
		<key>LSMinimumSystemVersion</key><string>13.0</string>
		<key>NSPrincipalClass</key><string>NSApplication</string>
	</dict>
	</plist>
	PLIST

	# conductor.json goes in BEFORE signing — it lives under the code seal
	# (replace-flow.md: a tampered conductor.json breaks the next verification).
	cat > "$app/Contents/Resources/conductor.json" <<-JSON
	{
	  "conductor": 1,
	  "update_url": "http://localhost:${PORT}/manifest.json",
	  "vendor_url": "http://localhost:${PORT}/"
	}
	JSON

	# The policy goes in BEFORE signing too: it is read from under the seal.
	[[ "$policy" == "policy" ]] && write_policy "$app"

	clang -fobjc-arc -mmacosx-version-min=13.0 -framework Cocoa \
		-o "$app/Contents/MacOS/ConductorTestee" testee-main.m

	if [[ "$posture" == "none" ]]; then
		codesign --force --options runtime --timestamp \
			--sign "$IDENTITY" "$app"
	else
		# Kept beside the version folders, not inside one: each of those is
		# packed whole into a DMG that must hold exactly one .app.
		write_entitlements "$posture" "$BUILD/entitlements-$posture.plist"
		codesign --force --options runtime --timestamp \
			--entitlements "$BUILD/entitlements-$posture.plist" \
			--sign "$IDENTITY" "$app"
	fi
	echo "built + signed ConductorTestee ${version} (${buildnum}) — ${posture}${policy:+, with policy}"
}

build_app 1.0 100 "$BUILD/v1.0" sandbox
build_app 1.1 110 "$BUILD/v1.1" sandbox
build_app 1.2 120 "$BUILD/v1.2" sandbox-client policy
build_app 1.3 130 "$BUILD/v1.3" sandbox-client
build_app 0.9 90  "$BUILD/v0.9" none

if [[ "$NOTARIZE" == 1 ]]; then
	for v in v1.0 v1.1 v1.2 v1.3 v0.9; do
		zip="$BUILD/$v/ConductorTestee.zip"
		ditto -ck --keepParent "$BUILD/$v/ConductorTestee.app" "$zip"
		echo "notarizing $v …"
		xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
		xcrun stapler staple "$BUILD/$v/ConductorTestee.app"
		rm "$zip"
	done
fi

# v1.0: the starting install. v1.1: lets the M2 retraction drill simulate a
# completed install (State B) without requiring notarized artifacts.
ditto "$BUILD/v1.0/ConductorTestee.app" "$SERVE/ConductorTestee-1.0.app"
ditto "$BUILD/v1.1/ConductorTestee.app" "$SERVE/ConductorTestee-1.1.app"
# v0.9: the unsandboxed starting install for the "drops network access" path.
ditto "$BUILD/v0.9/ConductorTestee.app" "$SERVE/ConductorTestee-0.9.app"

# v1.1: the update artifact, DMG (primary) and zip (alternate path).
hdiutil create -srcfolder "$BUILD/v1.1" -volname "ConductorTestee" \
	-fs APFS -format UDZO -quiet "$SERVE/ConductorTestee-1.1.dmg"
ditto -ck --keepParent "$BUILD/v1.1/ConductorTestee.app" "$SERVE/ConductorTestee-1.1.zip"

# Network-gate artifacts (CND-7): the two builds that gain internet access.
for v in 1.2 1.3; do
	hdiutil create -srcfolder "$BUILD/v$v" -volname "ConductorTestee" \
		-fs APFS -format UDZO -quiet "$SERVE/ConductorTestee-$v.dmg"
done

# Replay-attack artifact: v1.0 packaged as if it were an update. A manifest
# pointing here simulates a hijacked URL serving an older validly-signed build;
# Conductor must refuse at the staged-version check (replace-flow.md §3.2).
hdiutil create -srcfolder "$BUILD/v1.0" -volname "ConductorTestee" \
	-fs APFS -format UDZO -quiet "$SERVE/ConductorTestee-1.0.dmg"

# Ad-hoc-signed v1.1: simulates an attacker without the vendor's Developer ID
# identity. Must fail the pinned Team ID requirement.
mkdir -p "$BUILD/v1.1-adhoc"
ditto "$BUILD/v1.1/ConductorTestee.app" "$BUILD/v1.1-adhoc/ConductorTestee.app"
codesign --force --sign - "$BUILD/v1.1-adhoc/ConductorTestee.app"
hdiutil create -srcfolder "$BUILD/v1.1-adhoc" -volname "ConductorTestee" \
	-fs APFS -format UDZO -quiet "$SERVE/ConductorTestee-1.1-adhoc.dmg"

SHA256=$(shasum -a 256 "$SERVE/ConductorTestee-1.1.dmg" | cut -d' ' -f1)
SIZE=$(stat -f %z "$SERVE/ConductorTestee-1.1.dmg")

# The main manifest carries release notes (spec.md §3.5) that exercise every
# rule: one note of each of the seven developer types (deliberately NOT in
# render order), one unknown type and one forged "retracted" (both must be
# dropped, logged and counted), and a `history` whose 1.0.5 entry sits
# strictly between 1.0 and 1.1 (rendered as a skipped version) while its 1.0
# and 1.1 entries must be ignored. Keys are one per line so the sed-derived
# manifests below keep matching only the top-level "version"/"build".
cat > "$SERVE/manifest.json" <<-JSON
{
  "conductor_manifest": 1,
  "bundle_id": "com.ranvel.conductor-testee",
  "version": "1.1",
  "build": "110",
  "url": "http://localhost:${PORT}/ConductorTestee-1.1.dmg",
  "sha256": "${SHA256}",
  "size": ${SIZE},
  "released": "$(date +%Y-%m-%d)",
  "changelog_url": "http://localhost:${PORT}/",
  "notes": [
    {"type": "fixed", "text": "The version label no longer clips at large text sizes."},
    {"type": "improved", "text": "The window opens centered on the active display."},
    {"type": "added", "text": "Shows the build number next to the version."},
    {"type": "security", "text": "Hardened runtime is now enforced for every helper."},
    {"type": "disabled", "text": "The experimental dark title bar is off while it is reworked."},
    {"type": "removed", "text": "The legacy 1.0 greeting. Nothing replaces it."},
    {"type": "notice", "text": "Settings move to a new format on first launch. 1.0 cannot read them afterwards."},
    {"type": "deprecated", "text": "A type from a vocabulary this Conductor does not know."},
    {"type": "retracted", "text": "Forged: a manifest may never say this."},
    {"type": "fixed", "text": "Quitting from the Dock no longer leaves the window on screen."}
  ],
  "history": [
    {"version": "1.1", "date": "2026-01-01", "notes": [
      {"type": "removed", "text": "Ignored: history may not describe the advertised version."}]},
    {"version": "1.0.5", "date": "2026-10-14", "notes": [
      {"type": "added", "text": "A 1.0.5 feature the user skipped."},
      {"type": "fixed", "text": "A 1.0.5 fix the user skipped."}]},
    {"version": "1.0", "date": "2026-09-01", "notes": [
      {"type": "added", "text": "Ignored: the user already has 1.0."}]}
  ]
}
JSON

# Network-gate manifests: 1.2 gains access and says why, 1.3 gains it and
# doesn't. No notes — these are about the gate.
for pair in "1.2 120" "1.3 130"; do
	v="${pair% *}"; b="${pair#* }"
	cat > "$SERVE/manifest-$v.json" <<-JSON
	{
	  "conductor_manifest": 1,
	  "bundle_id": "com.ranvel.conductor-testee",
	  "version": "$v",
	  "build": "$b",
	  "url": "http://localhost:${PORT}/ConductorTestee-$v.dmg",
	  "sha256": "$(shasum -a 256 "$SERVE/ConductorTestee-$v.dmg" | cut -d' ' -f1)",
	  "changelog_url": "http://localhost:${PORT}/"
	}
	JSON
done

# Negative-test manifests.
sed -e 's/^  "version": "1.1"/  "version": "0.9"/' -e 's/"build": "110"/"build": "90"/' \
	"$SERVE/manifest.json" > "$SERVE/manifest-downgrade.json"
sed -e 's/com.ranvel.conductor-testee/com.wrong.bundle-id/' \
	"$SERVE/manifest.json" > "$SERVE/manifest-wrong-bundle.json"

# Retraction manifest (retraction.md): the vendor swapped the manifest back to
# 1.0 after promoting 1.1 — legitimately advertising the older build, unlike
# manifest-downgrade.json (0.9, the in-operation refusal test). Points at the
# genuine 1.0 DMG.
SHA256_V10=$(shasum -a 256 "$SERVE/ConductorTestee-1.0.dmg" | cut -d' ' -f1)
sed -e 's/^  "version": "1.1"/  "version": "1.0"/' -e 's/"build": "110"/"build": "100"/' \
	-e "s/ConductorTestee-1.1.dmg/ConductorTestee-1.0.dmg/" \
	-e "s/\"sha256\": \"${SHA256}\"/\"sha256\": \"${SHA256_V10}\"/" \
	"$SERVE/manifest.json" > "$SERVE/manifest-retracted.json"

# Urgency manifest (deferral.md): same 1.1 payload flagged data_loss — must
# bypass the soak window only, nothing else.
cat > "$SERVE/manifest-urgent.json" <<-JSON
{
  "conductor_manifest": 1,
  "bundle_id": "com.ranvel.conductor-testee",
  "version": "1.1",
  "build": "110",
  "url": "http://localhost:${PORT}/ConductorTestee-1.1.dmg",
  "sha256": "${SHA256}",
  "urgency": "data_loss",
  "changelog_url": "http://localhost:${PORT}/"
}
JSON

# Replay manifest: advertises "1.2" but its artifact is the v1.0 build.
SHA256_REPLAY=$(shasum -a 256 "$SERVE/ConductorTestee-1.0.dmg" | cut -d' ' -f1)
sed -e 's/^  "version": "1.1"/  "version": "1.2"/' -e 's/"build": "110"/"build": "120"/' \
	-e "s/ConductorTestee-1.1.dmg/ConductorTestee-1.0.dmg/" \
	-e "s/\"sha256\": \"${SHA256}\"/\"sha256\": \"${SHA256_REPLAY}\"/" \
	"$SERVE/manifest.json" > "$SERVE/manifest-replay.json"

# Ad-hoc manifest: the 1.1 payload signed without the vendor's identity.
SHA256_ADHOC=$(shasum -a 256 "$SERVE/ConductorTestee-1.1-adhoc.dmg" | cut -d' ' -f1)
sed -e "s/ConductorTestee-1.1.dmg/ConductorTestee-1.1-adhoc.dmg/" \
	-e "s/\"sha256\": \"${SHA256}\"/\"sha256\": \"${SHA256_ADHOC}\"/" \
	"$SERVE/manifest.json" > "$SERVE/manifest-adhoc.json"

echo
echo "Artifacts in $(pwd)/$SERVE:"
ls -l "$SERVE"
echo
echo "E2E recipe:"
echo "  1. (cd $(pwd)/$SERVE && python3 -m http.server ${PORT})"
echo "  2. ditto $SERVE/ConductorTestee-1.0.app /Applications/ConductorTestee.app"
echo "  3. Run Conductor with arguments: --dev-mode com.ranvel.conductor-testee"
echo "  4. Check → Install → observe verify/swap in the log."
if [[ "$NOTARIZE" != 1 ]]; then
	echo
	echo "NOTE: not notarized — Conductor will refuse at the notarization step."
	echo "Store credentials once with:"
	echo "  xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <id> --team-id F252L9GUBW"
	echo "then re-run with --notarize for the full positive path."
fi
