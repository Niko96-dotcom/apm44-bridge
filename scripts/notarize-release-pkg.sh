#!/usr/bin/env bash
# Notarize and staple the release pkg (SHIP-02).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

# shellcheck source=scripts/notary-result.sh
source "$ROOT/scripts/notary-result.sh"

if [[ ! -f "$PKG" ]]; then
  echo "error: pkg not found at $PKG — run scripts/build-release-pkg.sh first" >&2
  exit 1
fi

require_developer_id_installer_signature() {
  echo "Checking pkg signature..."
  local signature
  if ! signature="$(pkgutil --check-signature "$PKG" 2>&1)"; then
    printf '%s\n' "$signature" >&2
    echo "error: pkg signature check failed - run scripts/build-release-pkg.sh with INSTALLER_SIGN_ID" >&2
    exit 1
  fi
  if ! printf '%s\n' "$signature" | grep -q "Developer ID Installer"; then
    printf '%s\n' "$signature" >&2
    echo "error: pkg is not signed by a Developer ID Installer identity - run scripts/build-release-pkg.sh with INSTALLER_SIGN_ID" >&2
    exit 1
  fi
}

require_developer_id_installer_signature
require_notary_accepted "$PKG" "$PROFILE" "pkg"

echo "Stapling pkg..."
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"

require_developer_id_installer_signature

echo "Assessing pkg with Gatekeeper..."
spctl --assess --type install --verbose=4 "$PKG"

echo "Writing pkg checksum..."
(
  cd "$(dirname "$PKG")"
  shasum -a 256 "$(basename "$PKG")" >"$(basename "$PKG").sha256"
)
echo "Checksum ready: $PKG.sha256"
echo "Notarized pkg ready: $PKG"
