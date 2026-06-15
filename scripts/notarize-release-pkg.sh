#!/usr/bin/env bash
# Notarize and staple the release pkg (SHIP-02).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.10.0}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

# shellcheck source=scripts/notary-result.sh
source "$ROOT/scripts/notary-result.sh"

if [[ ! -f "$PKG" ]]; then
  echo "error: pkg not found at $PKG — run scripts/build-release-pkg.sh first" >&2
  exit 1
fi

INSTALLER_ID="${INSTALLER_SIGN_ID:-}"
if [[ -z "$INSTALLER_ID" ]]; then
  if identities="$(security find-identity -v -p basic 2>/dev/null)"; then
    INSTALLER_ID="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Installer: .*\)".*/\1/p' | sed -n '1p')"
  else
    INSTALLER_ID=""
  fi
fi

if [[ -z "$INSTALLER_ID" ]] || ! security find-identity -v | grep -qF "$INSTALLER_ID"; then
  echo "error: pkg is unsigned — create a Developer ID Installer cert in Apple Developer," >&2
  echo "  then set INSTALLER_SIGN_ID and run scripts/build-release-pkg.sh before notarizing." >&2
  echo "  Or ship the notarized DMG: bash scripts/notarize-release-dmg.sh" >&2
  exit 1
fi

require_notary_accepted "$PKG" "$PROFILE" "pkg"

echo "Stapling pkg..."
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
echo "Notarized pkg ready: $PKG"
