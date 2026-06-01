#!/usr/bin/env bash
# Build notarized-ready DMG with app + HAL driver (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="${APM44_VERSION:-0.1.0}"
OUT="${APM44_DMG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.dmg}"
STAGING="${APM44_DMG_STAGING:-$ROOT/build/signing/dmg-staging}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: build-release-dmg.sh [--help]

Build Release artifacts, embed daemon, sign, and create a DMG for distribution.

Prerequisites: Developer ID cert, optional notarization (scripts/notary-dry-run.sh)

Output: build/signing/APM44Bridge-<version>.dmg
EOF
  exit 0
fi

echo "Building Release…"
cmake -S "$ROOT" -B "$ROOT/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/build" --target apm44-bridge APM44Bridge

if [[ ! -d "$ROOT/App/APM44Bridge.xcodeproj" ]]; then
  (cd "$ROOT/App" && xcodegen generate)
fi
xcodebuild -project "$ROOT/App/APM44Bridge.xcodeproj" -scheme APM44Bridge \
  -configuration "$CONFIG" build CODE_SIGNING_ALLOWED=NO \
  CONFIGURATION_BUILD_DIR="$ROOT/build/$CONFIG"

bash "$ROOT/scripts/embed-daemon-in-app.sh"

if [[ -n "${SIGN_ID:-}" ]] || security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
  bash "$ROOT/scripts/sign-release.sh"
fi

APP="$ROOT/build/$CONFIG/APM44 Bridge.app"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/APM44 Bridge.app"
ditto "$DRIVER" "$STAGING/APM44Bridge.driver"
cat > "$STAGING/Install APM44 Bridge.command" <<CMD
#!/bin/bash
set -euo pipefail
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
echo "Installing APM44 Bridge (requires admin password)…"
sudo ditto "\$DIR/APM44Bridge.driver" /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo xattr -cr /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
sudo killall coreaudiod 2>/dev/null || true
cp -R "\$DIR/APM44 Bridge.app" /Applications/
open "/Applications/APM44 Bridge.app"
echo "Done. If APM44 Bridge does not appear in Audio MIDI Setup, reboot once."
CMD
chmod +x "$STAGING/Install APM44 Bridge.command"

rm -f "$OUT"
hdiutil create -volname "APM44 Bridge" -srcfolder "$STAGING" -ov -format UDZO "$OUT"
echo "DMG created: $OUT"
echo "Install: open DMG → run Install APM44 Bridge.command → drag app to Applications"
