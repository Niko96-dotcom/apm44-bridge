#!/usr/bin/env bash
# Zip, notarize, and staple APM44Bridge.driver so macOS 15+ will load it in coreaudiod.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
ZIP="${APM44_NOTARY_ZIP:-$ROOT/build/signing/APM44Bridge-driver.zip}"

if [[ ! -d "$DRIVER" ]]; then
  echo "error: driver not found at $DRIVER" >&2
  echo "Build: cmake --build build --target APM44Bridge" >&2
  exit 1
fi

if ! codesign --verify --deep --strict "$DRIVER" 2>/dev/null; then
  echo "error: driver is not validly signed — sign with Developer ID first (see docs/release.md)" >&2
  exit 1
fi

mkdir -p "$(dirname "$ZIP")"
xattr -cr "$DRIVER" 2>/dev/null || true

echo "Packaging $DRIVER -> $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$DRIVER" "$ZIP"

echo "Submitting to Apple notary service (profile: $PROFILE)..."
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "Stapling ticket to driver bundle..."
xcrun stapler staple "$DRIVER"
xcrun stapler validate "$DRIVER"

echo ""
spctl -a -vv -t install "$DRIVER" 2>&1 || true
echo ""
echo "Notarized driver ready. Reinstall:"
echo "  APM44_DRIVER_PATH=\"$DRIVER\" bash scripts/install-driver.sh"
echo "  bash scripts/reload-coreaudio.sh"
echo ""
echo "If APM44 Bridge still does not appear in Audio MIDI Setup, reboot once."
