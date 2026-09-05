#!/usr/bin/env bash
# Verify the public release PKG without installing it by default.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"
PROVENANCE="$PKG.provenance.txt"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "$2"
}

require_developer_id_installer_signature() {
  local signature
  signature="$(pkgutil --check-signature "$PKG" 2>&1)" || {
    printf '%s\n' "$signature" >&2
    fail "pkg signature check failed"
  }
  grep -q "Developer ID Installer" <<<"$signature" || {
    printf '%s\n' "$signature" >&2
    fail "pkg is not signed by a Developer ID Installer identity"
  }
}

require_payload_path() {
  local payload="$1"
  local needle="$2"
  grep -Fq "$needle" <<<"$payload" || fail "pkg payload missing $needle"
}

require_script_marker() {
  local script="$1"
  local marker="$2"
  grep -Fq "$marker" "$script" || fail "$(basename "$script") missing marker: $marker"
}

first_line() {
  awk 'NF { print; exit }'
}

parse_build_id() {
  local out="$1"
  if [[ "$out" =~ build=([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$out" =~ helper_build_id=([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf 'unavailable\n'
  fi
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

bundle_file_hash() {
  local bundle="$1"
  [[ -d "$bundle" ]] || fail "app bundle not found at $bundle"
  find "$bundle" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}'
}

[[ -f "$PKG" ]] || fail "pkg not found at $PKG - run bash scripts/release-all.sh first"

echo "Checking pkg signature..."
require_developer_id_installer_signature

echo "Validating stapled ticket..."
xcrun stapler validate "$PKG"

echo "Assessing pkg with Gatekeeper..."
spctl --assess --type install --verbose=4 "$PKG"

checksum="$PKG.sha256"
[[ -f "$checksum" ]] || fail "missing pkg checksum at $checksum"
echo "Checking pkg checksum..."
(
  cd "$(dirname "$PKG")"
  shasum -a 256 -c "$(basename "$checksum")"
)

echo "Checking pkg payload..."
payload="$(pkgutil --payload-files "$PKG")"
require_payload_path "$payload" "Applications/APM44 Bridge.app"
require_payload_path "$payload" "Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"

echo "Checking pkg install scripts..."
expanded="$TMP/expanded"
pkgutil --expand-full "$PKG" "$expanded"
preinstall="$(find "$expanded" -type f -name preinstall | head -1)"
postinstall="$(find "$expanded" -type f -name postinstall | head -1)"
[[ -n "$preinstall" ]] || fail "expanded pkg missing preinstall"
[[ -n "$postinstall" ]] || fail "expanded pkg missing postinstall"
require_script_marker "$preinstall" 'rm -rf "/Applications/APM44 Bridge.app"'
require_script_marker "$preinstall" 'rm -rf "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"'
require_script_marker "$preinstall" 'Terminating running APM44 Bridge before replacing the app'
require_script_marker "$preinstall" 'pkill -KILL -f "$APP_PATTERN"'
require_script_marker "$postinstall" "APM44 Bridge.app missing after install"
require_script_marker "$postinstall" "APM44Bridge.driver missing after install"
require_script_marker "$postinstall" "Installed app/driver/helper build ID mismatch"

BRIDGE="${APM44_BRIDGE_BIN:-$ROOT/build/BridgeDaemon/apm44-bridge}"
version_out="unavailable"
if [[ -x "$BRIDGE" ]]; then
  version_out="$("$BRIDGE" --version 2>/dev/null || true)"
fi
bridge_version="$(printf '%s\n' "$version_out" | first_line)"
[[ -n "$bridge_version" ]] || bridge_version="unavailable"
helper_build_id="$(parse_build_id "$version_out")"

APP="${APM44_APP_PATH:-$ROOT/build/Release/APM44 Bridge.app}"
DRIVER_EXE="${APM44_DRIVER_EXECUTABLE:-$ROOT/build/Driver/APM44Bridge.driver/Contents/MacOS/APM44Bridge}"
require_file "$DRIVER_EXE" "driver executable not found at $DRIVER_EXE"

echo "Writing pkg provenance..."
{
  echo "pkg_path=$PKG"
  echo "pkg_sha256=$(sha256 "$PKG")"
  echo "git_head=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  echo "bridge_version=$bridge_version"
  echo "helper_build_id=$helper_build_id"
  echo "app_bundle_sha256=$(bundle_file_hash "$APP")"
  echo "driver_executable_sha256=$(sha256 "$DRIVER_EXE")"
} >"$PROVENANCE"
echo "Provenance ready: $PROVENANCE"

if [[ "${APM44_RUN_PKG_INSTALL_SMOKE:-0}" == "1" ]]; then
  echo "Running explicit pkg install smoke..."
  sudo installer -pkg "$PKG" -target /
  APM44_APP_PATH="/Applications/APM44 Bridge.app" bash "$ROOT/scripts/verify-installed-sync.sh"
  bash "$ROOT/scripts/verify-hal-driver.sh"
  "$ROOT/build/BridgeDaemon/apm44-bridge" --shm-status
else
  echo "Skipping install smoke; set APM44_RUN_PKG_INSTALL_SMOKE=1 to install into /Applications and HAL."
fi

echo "verify-release-pkg: OK"
