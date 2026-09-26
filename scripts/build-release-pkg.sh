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
COMPONENT_PLIST="$ROOT/build/signing/pkg-components.plist"
rm -rf "$PAYLOAD" "$SCRIPTS" "$COMPONENT_PLIST"
mkdir -p "$PAYLOAD/Applications"
mkdir -p "$PAYLOAD/Library/Audio/Plug-Ins/HAL"
mkdir -p "$SCRIPTS"

ditto "$APP" "$PAYLOAD/Applications/APM44 Bridge.app"
ditto "$DRIVER" "$PAYLOAD/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"

pkgbuild --analyze --root "$PAYLOAD" "$COMPONENT_PLIST"

python3 - "$COMPONENT_PLIST" <<'PYEOF'
import plistlib
import sys
path = sys.argv[1]
with open(path, 'rb') as f:
    data = plistlib.load(f)

def fix_bundle(d):
    if not isinstance(d, dict):
        return
    d['BundleIsRelocatable'] = False
    d['BundleIsVersionChecked'] = False
    if 'BundleOverwriteAction' not in d:
        d['BundleOverwriteAction'] = 'upgrade'
    child = d.get('ChildBundles')
    if isinstance(child, list):
        for c in child:
            fix_bundle(c)

if isinstance(data, list):
    for entry in data:
        fix_bundle(entry)
elif isinstance(data, dict):
    def walk(o):
        if isinstance(o, dict):
            if 'RootRelativeBundlePath' in o:
                fix_bundle(o)
            else:
                for v in o.values():
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(data)
else:
    print('error: unexpected component plist top-level type', file=sys.stderr)
    sys.exit(1)

def collect_paths(o, out):
    if isinstance(o, dict):
        if 'RootRelativeBundlePath' in o:
            out.append(o.get('RootRelativeBundlePath'))
        for v in o.values():
            if isinstance(v, (dict, list)):
                collect_paths(v, out)
    elif isinstance(o, list):
        for v in o:
            collect_paths(v, out)

paths = []
collect_paths(data, paths)
if 'Applications/APM44 Bridge.app' not in paths:
    print('error: component plist missing Applications/APM44 Bridge.app', file=sys.stderr)
    sys.exit(1)
if 'Library/Audio/Plug-Ins/HAL/APM44Bridge.driver' not in paths:
    print('error: component plist missing Library/Audio/Plug-Ins/HAL/APM44Bridge.driver', file=sys.stderr)
    sys.exit(1)

with open(path, 'wb') as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)
PYEOF

cat > "$SCRIPTS/preinstall" <<'PRE'
#!/bin/bash
set -e
# Downgrade guard: refuse to replace a newer installed version with this older package.
PKG_VERSION="@APM44_PKG_VERSION@"
TARGET="${3:-/}"
# The replacement below always targets the startup disk, so installing onto
# another volume would check one volume and delete from another.
if [[ "$TARGET" != "/" && "${APM44_PREINSTALL_GUARD_ONLY:-}" != "1" ]]; then
  echo "APM44 Bridge can only be installed on the startup disk (target: $TARGET)." >&2
  exit 1
fi
if [[ "$TARGET" == "/" ]]; then
  APP_INFO_PLIST="/Applications/APM44 Bridge.app/Contents/Info.plist"
  DRIVER_INFO_PLIST="/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/Info.plist"
else
  TARGET_TRIMMED="${TARGET%/}"
  APP_INFO_PLIST="$TARGET_TRIMMED/Applications/APM44 Bridge.app/Contents/Info.plist"
  DRIVER_INFO_PLIST="$TARGET_TRIMMED/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/Info.plist"
fi
INSTALLED_APP_VERSION=""
INSTALLED_DRIVER_VERSION=""
if [[ -f "$APP_INFO_PLIST" ]]; then
  INSTALLED_APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' "$APP_INFO_PLIST" 2>/dev/null || true)"
fi
if [[ -f "$DRIVER_INFO_PLIST" ]]; then
  INSTALLED_DRIVER_VERSION="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' "$DRIVER_INFO_PLIST" 2>/dev/null || true)"
fi
apm44_version_is_numeric() {
  local _apm44_v="$1"
  if [[ -z "$_apm44_v" ]]; then
    return 1
  fi
  case "$_apm44_v" in
    *[!0-9.]* ) return 1 ;;
  esac
  case "$_apm44_v" in
    .*|*.|*..*) return 1 ;;
  esac
  case "$_apm44_v" in
    *[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) return 1 ;;
  esac
  return 0
}
# Fail closed: a present but unparseable installed version could be newer.
apm44_require_parseable() {
  local _apm44_label="$1"
  local _apm44_v="$2"
  [[ -z "$_apm44_v" ]] && return 0
  apm44_version_is_numeric "$_apm44_v" && return 0
  echo "Cannot compare the installed APM44 Bridge $_apm44_label version \"$_apm44_v\"; remove it and run the installer again." >&2
  exit 1
}
apm44_version_gt() {
  local _apm44_a="$1"
  local _apm44_b="$2"
  apm44_version_is_numeric "$_apm44_a" || return 1
  apm44_version_is_numeric "$_apm44_b" || return 1
  local _apm44_a_rest="$_apm44_a"
  local _apm44_b_rest="$_apm44_b"
  local _apm44_a_part=""
  local _apm44_b_part=""
  while [[ -n "$_apm44_a_rest" || -n "$_apm44_b_rest" ]]; do
    case "$_apm44_a_rest" in
      *.*)
        _apm44_a_part="${_apm44_a_rest%%.*}"
        _apm44_a_rest="${_apm44_a_rest#*.}"
        ;;
      *)
        _apm44_a_part="$_apm44_a_rest"
        _apm44_a_rest=""
        ;;
    esac
    case "$_apm44_b_rest" in
      *.*)
        _apm44_b_part="${_apm44_b_rest%%.*}"
        _apm44_b_rest="${_apm44_b_rest#*.}"
        ;;
      *)
        _apm44_b_part="$_apm44_b_rest"
        _apm44_b_rest=""
        ;;
    esac
    if [[ -z "$_apm44_a_part" ]]; then
      _apm44_a_part="0"
    fi
    if [[ -z "$_apm44_b_part" ]]; then
      _apm44_b_part="0"
    fi
    if (( 10#$_apm44_a_part > 10#$_apm44_b_part )); then
      return 0
    fi
    if (( 10#$_apm44_a_part < 10#$_apm44_b_part )); then
      return 1
    fi
  done
  return 1
}
apm44_require_parseable app "$INSTALLED_APP_VERSION"
apm44_require_parseable driver "$INSTALLED_DRIVER_VERSION"
if apm44_version_gt "$INSTALLED_APP_VERSION" "$PKG_VERSION"; then
  echo "APM44 Bridge $INSTALLED_APP_VERSION is already installed; refusing to replace it with older $PKG_VERSION." >&2
  exit 1
fi
if apm44_version_gt "$INSTALLED_DRIVER_VERSION" "$PKG_VERSION"; then
  echo "APM44 Bridge $INSTALLED_DRIVER_VERSION is already installed; refusing to replace it with older $PKG_VERSION." >&2
  exit 1
fi
if [[ "${APM44_PREINSTALL_GUARD_ONLY:-}" == "1" ]]; then
  exit 0
fi
# Ask the existing app to quit, then terminate only helpers launched from the
# installed app bundle. This avoids replacing a running old process image.
CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(stat -f%u /dev/console 2>/dev/null || true)"
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" && "$CONSOLE_UID" =~ ^[0-9]+$ ]]; then
  launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" \
    osascript -e 'tell application id "com.niko.apm44.menu" to quit' 2>/dev/null || true
fi
APP_PATTERN='^/Applications/APM44 Bridge.app/Contents/MacOS/APM44 Bridge([[:space:]]|$)'
for _ in {1..20}; do
  pgrep -f "$APP_PATTERN" >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -f "$APP_PATTERN" >/dev/null 2>&1; then
  echo "Terminating running APM44 Bridge before replacing the app" >&2
  pkill -TERM -f "$APP_PATTERN" 2>/dev/null || true
  sleep 1
fi
if pgrep -f "$APP_PATTERN" >/dev/null 2>&1; then
  pkill -KILL -f "$APP_PATTERN" 2>/dev/null || true
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
PREINSTALL_TMP="$SCRIPTS/preinstall.tmp"
sed "s/@APM44_PKG_VERSION@/$VERSION/g" "$SCRIPTS/preinstall" > "$PREINSTALL_TMP"
mv "$PREINSTALL_TMP" "$SCRIPTS/preinstall"
chmod +x "$SCRIPTS/preinstall"
if grep -Fq "@APM44_PKG_VERSION@" "$SCRIPTS/preinstall"; then
  echo "error: preinstall version placeholder not substituted" >&2
  exit 1
fi

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
APP_BUILD_ID="$(/usr/libexec/PlistBuddy -c 'Print:APM44BuildID' '/Applications/APM44 Bridge.app/Contents/Info.plist' 2>/dev/null || true)"
DRIVER_BUILD_ID="$(/usr/libexec/PlistBuddy -c 'Print:APM44BuildID' '/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/Info.plist' 2>/dev/null || true)"
HELPER_BUILD_ID="$(printf '%s\n' "$HELPER_VERSION" | sed -n 's/.*build=\([^[:space:]]*\).*/\1/p')"
[[ -n "$APP_BUILD_ID" && "$APP_BUILD_ID" == "$DRIVER_BUILD_ID" && "$APP_BUILD_ID" == "$HELPER_BUILD_ID" ]] || {
  echo "Installed app/driver/helper build ID mismatch: app=$APP_BUILD_ID driver=$DRIVER_BUILD_ID helper=$HELPER_BUILD_ID" >&2
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
# Skip the relaunch for command-line installs (COMMAND_LINE_INSTALL=1):
# Sparkle installs via /usr/sbin/installer and relaunches the app itself.
# Launching the new app here, while Sparkle's install and relaunch session
# is still in flight, makes Sparkle report a failed update.
if [[ -z "${COMMAND_LINE_INSTALL:-}" ]]; then
  CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
  if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" && -d "/Applications/APM44 Bridge.app" ]]; then
    sudo -u "$CONSOLE_USER" open "/Applications/APM44 Bridge.app" 2>/dev/null || true
  fi
fi
exit 0
POST
chmod +x "$SCRIPTS/postinstall"

mkdir -p "$(dirname "$PKG")"
rm -f "$PKG" "$UNSIGNED_PKG" "$LOCAL_UNSIGNED_PKG"
pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" \
  --component-plist "$COMPONENT_PLIST" \
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
