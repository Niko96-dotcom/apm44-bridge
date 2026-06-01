#!/usr/bin/env bash
# Build signed pkg installing HAL driver + menu bar app (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="${APM44_VERSION:-0.1.0}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
PAYLOAD="$ROOT/build/signing/pkg-root"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: build-release-pkg.sh [--help]

Build pkg with APM44 Bridge.app + APM44Bridge.driver + postinstall reload.

Output: build/signing/APM44Bridge-<version>.pkg
EOF
  exit 0
fi

bash "$ROOT/scripts/build-release-dmg.sh" 2>/dev/null || true

cmake -S "$ROOT" -B "$ROOT/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/build" --target apm44-bridge APM44Bridge
bash "$ROOT/scripts/embed-daemon-in-app.sh"
if security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
  bash "$ROOT/scripts/sign-release.sh"
fi

APP="$ROOT/build/$CONFIG/APM44 Bridge.app"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
SCRIPTS="$ROOT/build/signing/pkg-scripts"

rm -rf "$PAYLOAD" "$SCRIPTS"
mkdir -p "$PAYLOAD/Applications"
mkdir -p "$PAYLOAD/Library/Audio/Plug-Ins/HAL"
mkdir -p "$SCRIPTS"

ditto "$APP" "$PAYLOAD/Applications/APM44 Bridge.app"
ditto "$DRIVER" "$PAYLOAD/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"

cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
xattr -cr /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
killall coreaudiod 2>/dev/null || true
exit 0
POST
chmod +x "$SCRIPTS/postinstall"

mkdir -p "$(dirname "$PKG")"
pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" \
  --identifier com.niko.apm44.pkg --version "$VERSION" \
  "$PKG"

echo "PKG created: $PKG"
echo "Install: sudo installer -pkg \"$PKG\" -target /"
