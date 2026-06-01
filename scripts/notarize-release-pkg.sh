#!/usr/bin/env bash
# Notarize and staple the release pkg (SHIP-02).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.1.0}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

if [[ ! -f "$PKG" ]]; then
  echo "error: pkg not found at $PKG — run scripts/build-release-pkg.sh first" >&2
  exit 1
fi

INSTALLER_ID="${INSTALLER_SIGN_ID:-Developer ID Installer: Nikolay Mohr (4H5447ZWS3)}"
if ! security find-identity -v | grep -qF "$INSTALLER_ID"; then
  echo "error: pkg is unsigned — create a Developer ID Installer cert in Apple Developer," >&2
  echo "  then: productsign --sign \"$INSTALLER_ID\" ... before notarizing." >&2
  echo "  Or ship the notarized DMG: bash scripts/notarize-release-dmg.sh" >&2
  exit 1
fi

echo "Submitting pkg to notary (profile: $PROFILE)..."
RESULT=$(xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --wait 2>&1) || true
echo "$RESULT"
if echo "$RESULT" | grep -q "status: Invalid"; then
  ID=$(echo "$RESULT" | sed -n 's/.*id: \([^ ]*\).*/\1/p' | head -1)
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" 2>&1 | head -40
  exit 1
fi

echo "Stapling pkg..."
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
echo "Notarized pkg ready: $PKG"
