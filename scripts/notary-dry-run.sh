#!/usr/bin/env bash
# Package signed release artifacts and submit to Apple notary service (dry-run / staging).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
STAGING="${APM44_RELEASE_STAGING:-$ROOT/build/signing/release-staging}"
ZIP="${APM44_RELEASE_ZIP:-$ROOT/build/signing/APM44Bridge-release.zip}"

# shellcheck source=scripts/notary-result.sh
source "$ROOT/scripts/notary-result.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: notary-dry-run.sh [--help]

Zip signed app + daemon + driver. Submit via notarytool unless check-only.

Notarization is not required for local debug (use scripts/rebuild-and-open-app.sh
or scripts/ci.sh). This script is a distribution check.

Prerequisites:
  bash scripts/sign-release.sh
  xcrun notarytool store-credentials "$PROFILE"  (see scripts/setup-notary-profile.sh)
    unless APM44_NOTARY_CHECK_ONLY=1

Environment:
  NOTARY_PROFILE              keychain profile (default AC_NOTARY)
  APM44_NOTARY_CHECK_ONLY=1   zip and verify signatures; do not submit
  APM44_APP_PATH              path to .app bundle
  APM44_DAEMON_PATH           path to apm44-bridge binary
  APM44_DRIVER_PATH           path to .driver bundle
  APM44_RELEASE_STAGING       temp staging dir
  APM44_RELEASE_ZIP           output zip path
EOF
  exit 0
fi

APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"
DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

for artifact in "$APP" "$DAEMON" "$DRIVER"; do
  if [[ ! -e "$artifact" ]]; then
    echo "error: missing $artifact — build and sign first" >&2
    exit 1
  fi
  if ! codesign --verify --deep --strict "$artifact" 2>/dev/null; then
    echo "error: $artifact is not validly signed — run scripts/sign-release.sh" >&2
    exit 1
  fi
done

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/APM44 Bridge.app"
cp "$DAEMON" "$STAGING/apm44-bridge"
ditto "$DRIVER" "$STAGING/APM44Bridge.driver"

mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
echo "Creating release zip: $ZIP"
ditto -c -k --keepParent "$STAGING" "$ZIP"

if [[ "${APM44_NOTARY_CHECK_ONLY:-0}" == "1" ]]; then
  echo ""
  echo "Notary check-only: created $ZIP; did not submit to Apple."
  echo "Notarization is not required for local debug."
  echo "Submit this zip only for public-release evidence (omit APM44_NOTARY_CHECK_ONLY)."
  exit 0
fi

require_notary_accepted "$ZIP" "$PROFILE" "release zip"

echo ""
echo "Notary dry-run complete. Staple individual bundles after acceptance:"
echo "  xcrun stapler staple \"$APP\""
echo "  xcrun stapler staple \"$DRIVER\""
echo "  bash scripts/notarize-hal-driver.sh   # driver-only re-staple if needed"
echo ""
echo "Evidence: save submission output above for SHIP-02 sign-off."
