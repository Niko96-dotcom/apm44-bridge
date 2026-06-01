#!/usr/bin/env bash
# Notarize and staple the release DMG (works without Developer ID Installer cert).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.1.0}"
DMG="${APM44_DMG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.dmg}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

if [[ ! -f "$DMG" ]]; then
  echo "error: DMG not found at $DMG — run scripts/build-release-dmg.sh first" >&2
  exit 1
fi

echo "Submitting DMG to notary (profile: $PROFILE)..."
RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1) || true
echo "$RESULT"
if echo "$RESULT" | grep -q "status: Invalid"; then
  echo "error: notarization failed — fetch log with:" >&2
  echo "  xcrun notarytool log <id> --keychain-profile $PROFILE" >&2
  exit 1
fi

echo "Stapling DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarized DMG ready: $DMG"
