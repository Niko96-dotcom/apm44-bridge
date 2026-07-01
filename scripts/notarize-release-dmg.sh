#!/usr/bin/env bash
# Notarize and staple the release DMG (works without Developer ID Installer cert).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.12.0}"
DMG="${APM44_DMG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.dmg}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

# shellcheck source=scripts/notary-result.sh
source "$ROOT/scripts/notary-result.sh"

if [[ ! -f "$DMG" ]]; then
  echo "error: DMG not found at $DMG — run scripts/build-release-dmg.sh first" >&2
  exit 1
fi

require_notary_accepted "$DMG" "$PROFILE" "DMG"

echo "Stapling DMG..."
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Assessing DMG with Gatekeeper..."
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
echo "Writing DMG checksum..."
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")" >"$(basename "$DMG").sha256"
)
echo "Checksum ready: $DMG.sha256"
echo "Notarized DMG ready: $DMG"
