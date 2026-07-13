#!/usr/bin/env bash
# Verify final mounted DMG/PKG install path; install smoke is explicit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$($ROOT/scripts/read-version.sh)"
DMG="${APM44_DMG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.dmg}"
MOUNTED="${APM44_MOUNTED_DMG_PATH:-}"
TMP="$(mktemp -d)"
MOUNT=""
MOUNT_ATTACHED=0

cleanup() {
  if [[ "$MOUNT_ATTACHED" == "1" && -n "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

require_sudo_ready() {
  if ! sudo -n true 2>/dev/null; then
    fail "sudo is required for install smoke; run interactively once or configure sudo, then retry"
  fi
}

if [[ -n "$MOUNTED" ]]; then
  [[ -d "$MOUNTED" ]] || fail "mounted DMG path not found at $MOUNTED"
  MOUNT="$MOUNTED"
else
  [[ -f "$DMG" ]] || fail "DMG not found at $DMG - run bash scripts/release-all.sh first"
  MOUNT="$TMP/mount"
  mkdir -p "$MOUNT"
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
  MOUNT_ATTACHED=1
fi

pkg_count="$(find "$MOUNT" -maxdepth 1 -type f -name '*.pkg' | wc -l | tr -d ' ')"
[[ "$pkg_count" == "1" ]] || fail "expected exactly one top-level pkg in mounted final DMG"
PKG="$(find "$MOUNT" -maxdepth 1 -type f -name '*.pkg' | head -1)"

echo "Final install source: $PKG"
pkgutil --check-signature "$PKG" | grep -q "Developer ID Installer" || fail "mounted package is not Developer ID Installer signed"
xcrun stapler validate "$PKG"
spctl --assess --type install --verbose=4 "$PKG"

if [[ "${APM44_RUN_FINAL_INSTALL_SMOKE:-0}" == "1" ]]; then
  require_sudo_ready
  sudo installer -pkg "$PKG" -target /
  APM44_APP_PATH="/Applications/APM44 Bridge.app" bash "$ROOT/scripts/verify-installed-sync.sh"
  bash "$ROOT/scripts/verify-hal-driver.sh"
  "$ROOT/build/BridgeDaemon/apm44-bridge" --shm-status
else
  echo "Install smoke skipped; set APM44_RUN_FINAL_INSTALL_SMOKE=1 to install from the mounted final DMG."
fi

echo "verify-final-install-artifact: OK"
