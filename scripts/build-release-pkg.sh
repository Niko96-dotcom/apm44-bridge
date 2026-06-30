#!/usr/bin/env bash
# Build signed pkg installing HAL driver + menu bar app (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="${APM44_VERSION:-0.11.0}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
UNSIGNED_PKG="${PKG%.pkg}-unsigned.pkg"
PAYLOAD="$ROOT/build/signing/pkg-root"
INSTALLER_ID="${INSTALLER_SIGN_ID:-}"
G2_CA_URL="https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"
G2_CA="${APM44_DEVID_G2_CA:-/tmp/DeveloperIDG2CA.cer}"

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

resolve_installer_id() {
  if [[ -n "$INSTALLER_ID" ]]; then
    printf '%s\n' "$INSTALLER_ID"
    return
  fi

  local identities
  identities="$(security find-identity -v -p basic 2>/dev/null | sed -n 's/.*"\(Developer ID Installer: .*\)".*/\1/p' || true)"
  local count
  count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities"
  fi
}

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
set -e
chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
xattr -cr /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
DRIVER_BIN="$(find /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/MacOS -maxdepth 1 -type f | head -1)"
if [[ -z "$DRIVER_BIN" ]]; then
  echo "APM44Bridge.driver executable missing after install" >&2
  exit 1
fi
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

curl -fsSL -o "$G2_CA" "$G2_CA_URL"
security import "$G2_CA" -k ~/Library/Keychains/login.keychain-db 2>/dev/null || true

INSTALLER_ID="$(resolve_installer_id)"
if [[ -n "$INSTALLER_ID" ]] && security find-identity -v -p basic 2>/dev/null | grep -qF "$INSTALLER_ID"; then
  productsign --sign "$INSTALLER_ID" "$UNSIGNED_PKG" "$PKG"
  rm -f "$UNSIGNED_PKG"
  echo "Signed pkg: $PKG"
else
  mv "$UNSIGNED_PKG" "$PKG"
  echo "WARN: no Developer ID Installer identity — set INSTALLER_SIGN_ID or run scripts/install-installer-cert.sh first"
fi

echo ""
echo "PKG created: $PKG"
echo "Install: sudo installer -pkg \"$PKG\" -target /"
echo "Notarize: bash scripts/notarize-release-pkg.sh"
