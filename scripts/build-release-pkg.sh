#!/usr/bin/env bash
# Build signed pkg installing HAL driver + menu bar app (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="${APM44_VERSION:-0.1.0}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
UNSIGNED_PKG="${PKG%.pkg}-unsigned.pkg"
PAYLOAD="$ROOT/build/signing/pkg-root"
SIGN_ID="${SIGN_ID:-Developer ID Application: Nikolay Mohr (4H5447ZWS3)}"
INSTALLER_ID="${INSTALLER_SIGN_ID:-Developer ID Installer: Nikolay Mohr (4H5447ZWS3)}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: build-release-pkg.sh [--help]

Build pkg with stapled APM44 Bridge.app + APM44Bridge.driver + postinstall.

Prerequisites: run scripts/build-release-dmg.sh and staple app/driver first,
or pass through release-all.sh.

Output: build/signing/APM44Bridge-<version>.pkg
EOF
  exit 0
fi

APP="$ROOT/build/$CONFIG/APM44 Bridge.app"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

for artifact in "$APP" "$DRIVER"; do
  if [[ ! -e "$artifact" ]]; then
    echo "error: missing $artifact — run scripts/build-release-dmg.sh first" >&2
    exit 1
  fi
done

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
CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
if [[ -n "$CONSOLE_USER" && -d "/Applications/APM44 Bridge.app" ]]; then
  sudo -u "$CONSOLE_USER" open "/Applications/APM44 Bridge.app" 2>/dev/null || true
fi
exit 0
POST
chmod +x "$SCRIPTS/postinstall"

mkdir -p "$(dirname "$PKG")"
pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" \
  --identifier com.niko.apm44.pkg --version "$VERSION" \
  "$UNSIGNED_PKG"

if security find-identity -v | grep -qF "$INSTALLER_ID"; then
  productsign --sign "$INSTALLER_ID" "$UNSIGNED_PKG" "$PKG"
  rm -f "$UNSIGNED_PKG"
  echo "Signed pkg: $PKG"
else
  mv "$UNSIGNED_PKG" "$PKG"
  echo "WARN: no Developer ID Installer cert — pkg unsigned (notarize may still work for ad-hoc testing)"
fi

echo ""
echo "PKG created: $PKG"
echo "Install: sudo installer -pkg \"$PKG\" -target /"
echo "Notarize: bash scripts/notarize-release-pkg.sh"
