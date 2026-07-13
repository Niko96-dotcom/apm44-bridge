#!/usr/bin/env bash
# Build signed pkg installing HAL driver + menu bar app (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="$($ROOT/scripts/read-version.sh)"
[[ -z "${APM44_VERSION:-}" || "$APM44_VERSION" == "$VERSION" ]] || {
  echo "error: APM44_VERSION disagrees with canonical VERSION=$VERSION" >&2
  exit 1
}
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
UNSIGNED_PKG="${PKG%.pkg}-unsigned.pkg"
LOCAL_UNSIGNED_PKG="${PKG%.pkg}-local-unsigned.pkg"
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
    if [[ "$INSTALLER_ID" != Developer\ ID\ Installer:* ]] || ! security find-identity -v -p basic 2>/dev/null | grep -qF "$INSTALLER_ID"; then
      echo "error: INSTALLER_SIGN_ID must name a valid Developer ID Installer identity" >&2
      echo "  set INSTALLER_SIGN_ID=\"Developer ID Installer: Name (TEAMID)\"" >&2
      return 2
    fi
    printf '%s\n' "$INSTALLER_ID"
    return 0
  fi

  local identities
  identities="$(security find-identity -v -p basic 2>/dev/null | sed -n 's/.*"\(Developer ID Installer: .*\)".*/\1/p' | sed '/^$/d' || true)"
  local count
  if [[ -z "$identities" ]]; then
    count=0
  else
    count="$(printf '%s\n' "$identities" | wc -l | tr -d ' ')"
  fi
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities"
    return 0
  fi

  if [[ "${APM44_ALLOW_UNSIGNED_PKG:-0}" == "1" ]]; then
    return 1
  fi

  if [[ "$count" == "0" ]]; then
    echo "error: Developer ID Installer identity is required for public PKG output" >&2
    echo "  run scripts/create-installer-csr.sh, import with scripts/install-installer-cert.sh," >&2
    echo "  or set INSTALLER_SIGN_ID=\"Developer ID Installer: Name (TEAMID)\"" >&2
  else
    echo "error: multiple Developer ID Installer identities found" >&2
    printf '%s\n' "$identities" >&2
    echo "  set INSTALLER_SIGN_ID=\"Developer ID Installer: Name (TEAMID)\"" >&2
  fi
  return 2
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

cat > "$SCRIPTS/preinstall" <<'PRE'
#!/bin/bash
set -e
# Ask the existing app to quit, then terminate only helpers launched from the
# installed app bundle. This avoids replacing a running old process image.
CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(stat -f%u /dev/console 2>/dev/null || true)"
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" && "$CONSOLE_UID" =~ ^[0-9]+$ ]]; then
  launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" \
    osascript -e 'tell application id "com.niko.apm44.menu" to quit' 2>/dev/null || true
fi
HELPER_PATTERN='^/Applications/APM44 Bridge.app/Contents/MacOS/apm44-bridge([[:space:]]|$)'
for _ in {1..20}; do
  pgrep -f "$HELPER_PATTERN" >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -f "$HELPER_PATTERN" >/dev/null 2>&1; then
  pkill -TERM -f "$HELPER_PATTERN" 2>/dev/null || true
  sleep 1
fi
if pgrep -f "$HELPER_PATTERN" >/dev/null 2>&1; then
  pkill -KILL -f "$HELPER_PATTERN" 2>/dev/null || true
fi
rm -rf "/Applications/APM44 Bridge.app"
rm -rf "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
exit 0
PRE
chmod +x "$SCRIPTS/preinstall"

cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
set -e
chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
xattr -d com.apple.quarantine /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
[[ -d "/Applications/APM44 Bridge.app" ]] || { echo "APM44 Bridge.app missing after install" >&2; exit 1; }
[[ -d "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver" ]] || { echo "APM44Bridge.driver missing after install" >&2; exit 1; }
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' '/Applications/APM44 Bridge.app/Contents/Info.plist')"
DRIVER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' '/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/Info.plist')"
[[ "$APP_VERSION" == "$DRIVER_VERSION" ]] || {
  echo "Installed app/driver version mismatch: app=$APP_VERSION driver=$DRIVER_VERSION" >&2
  exit 1
}
HELPER_VERSION="$(/Applications/APM44\ Bridge.app/Contents/MacOS/apm44-bridge --version 2>/dev/null || true)"
[[ "$HELPER_VERSION" == "apm44-bridge $APP_VERSION "* ]] || {
  echo "Installed helper version mismatch: $HELPER_VERSION" >&2
  exit 1
}
DRIVER_BIN="$(find /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/MacOS -maxdepth 1 -type f | head -1)"
if [[ -z "$DRIVER_BIN" ]]; then
  echo "APM44Bridge.driver executable missing after install" >&2
  exit 1
fi
# Reload Core Audio so the freshly installed HAL driver is picked up without a
# reboot in the common case. launchctl kickstart -k is more reliable than a bare
# killall; fall back to killall on systems where it is unavailable. Best effort:
# the app also surfaces a "Reload audio driver" / restart-once path if a
# first-time install still needs a reboot to enumerate the device.
if ! launchctl kickstart -k system/com.apple.audio.coreaudiod 2>/dev/null; then
  killall coreaudiod 2>/dev/null || true
fi
# Let coreaudiod respawn and rescan HAL plug-ins before opening the app, so
# first-run setup does not render during the load gap and wrongly report the
# driver as missing.
sleep 4
CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" && -d "/Applications/APM44 Bridge.app" ]]; then
  sudo -u "$CONSOLE_USER" open "/Applications/APM44 Bridge.app" 2>/dev/null || true
fi
exit 0
POST
chmod +x "$SCRIPTS/postinstall"

mkdir -p "$(dirname "$PKG")"
rm -f "$PKG" "$UNSIGNED_PKG" "$LOCAL_UNSIGNED_PKG"
pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" \
  --identifier com.niko.apm44.pkg --version "$VERSION" \
  "$UNSIGNED_PKG"

curl -fsSL -o "$G2_CA" "$G2_CA_URL"
security import "$G2_CA" -k ~/Library/Keychains/login.keychain-db 2>/dev/null || true

if INSTALLER_ID="$(resolve_installer_id)"; then
  productsign --sign "$INSTALLER_ID" "$UNSIGNED_PKG" "$PKG"
  rm -f "$UNSIGNED_PKG"
  echo "Signed pkg: $PKG"
else
  resolve_status=$?
  if [[ "$resolve_status" == "1" && "${APM44_ALLOW_UNSIGNED_PKG:-0}" == "1" ]]; then
    mv "$UNSIGNED_PKG" "$LOCAL_UNSIGNED_PKG"
    echo "LOCAL-ONLY UNSIGNED PKG: $LOCAL_UNSIGNED_PKG"
    echo "This package is not publishable. Configure Developer ID Installer signing for public PKG output."
  else
    rm -f "$UNSIGNED_PKG"
    exit "$resolve_status"
  fi
fi

echo ""
if [[ -f "$PKG" ]]; then
  echo "PKG created: $PKG"
  echo "Install: sudo installer -pkg \"$PKG\" -target /"
  echo "Notarize: bash scripts/notarize-release-pkg.sh"
else
  echo "Local-only unsigned PKG created: $LOCAL_UNSIGNED_PKG"
fi
