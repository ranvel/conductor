#!/bin/zsh
#
# build-testee.sh — builds, signs, and packages ConductorTestee v1.0 and v1.1
# for Conductor's end-to-end dev-mode harness (see docs/replace-flow.md and
# docs/dev-mode.md).
#
# Output (in TestHarness/serve/):
#   ConductorTestee-1.0.app/   — install this into a target dir to start
#   ConductorTestee-1.1.dmg    — the update artifact Conductor downloads
#   ConductorTestee-1.1.zip    — same payload as zip (zip-path testing)
#   manifest.json              — the Conductor manifest advertising 1.1, with
#                                typed release notes + history (spec.md §3.5)
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

build_app() { # $1=short version  $2=build number  $3=output dir
	local version="$1" buildnum="$2" outdir="$3"
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

	clang -fobjc-arc -mmacosx-version-min=13.0 -framework Cocoa \
		-o "$app/Contents/MacOS/ConductorTestee" testee-main.m

	codesign --force --options runtime --timestamp \
		--sign "$IDENTITY" "$app"
	echo "built + signed ConductorTestee ${version} (${buildnum})"
}

build_app 1.0 100 "$BUILD/v1.0"
build_app 1.1 110 "$BUILD/v1.1"

if [[ "$NOTARIZE" == 1 ]]; then
	for v in v1.0 v1.1; do
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

# v1.1: the update artifact, DMG (primary) and zip (alternate path).
hdiutil create -srcfolder "$BUILD/v1.1" -volname "ConductorTestee" \
	-fs APFS -format UDZO -quiet "$SERVE/ConductorTestee-1.1.dmg"
ditto -ck --keepParent "$BUILD/v1.1/ConductorTestee.app" "$SERVE/ConductorTestee-1.1.zip"

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
