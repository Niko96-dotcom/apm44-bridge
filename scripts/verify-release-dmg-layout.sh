#!/usr/bin/env bash
# Verify that the final public DMG exposes the PKG installer, not raw internals.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${APM44_VERSION:-0.12.1}"
DMG="${APM44_DMG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.dmg}"
STAGING="${APM44_DMG_STAGING:-$ROOT/build/signing/dmg-staging}"
TMP="$(mktemp -d)"
MOUNT=""

cleanup() {
  if [[ -n "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

inspect_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || fail "layout directory not found at $dir"

  local pkg_count
  pkg_count="$(find "$dir" -maxdepth 1 -type f -name '*.pkg' | wc -l | tr -d ' ')"
  [[ "$pkg_count" == "1" ]] || fail "expected exactly one top-level pkg in final DMG layout"

  [[ ! -e "$dir/APM44 Bridge.app" ]] || fail "raw app bundle must not be exposed in final DMG"
  [[ ! -e "$dir/APM44Bridge.driver" ]] || fail "raw HAL driver must not be exposed in final DMG"
  [[ ! -e "$dir/Install APM44 Bridge.command" ]] || fail "command installer must not be exposed in final DMG"
  [[ -f "$dir/README.txt" ]] || fail "README.txt missing from final DMG layout"
}

if [[ "${APM44_VERIFY_DMG_STAGING:-0}" == "1" ]]; then
  inspect_dir "$STAGING"
else
  [[ -f "$DMG" ]] || fail "DMG not found at $DMG - run bash scripts/release-all.sh first"
  MOUNT="$TMP/mount"
  mkdir -p "$MOUNT"
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
  inspect_dir "$MOUNT"
fi

echo "verify-release-dmg-layout: OK"
