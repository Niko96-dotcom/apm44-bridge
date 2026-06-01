#!/usr/bin/env bash
# Install APM44Bridge.driver to /Library/Audio/Plug-Ins/HAL/ with ad-hoc sign (dev only).
# Production: Developer ID sign per docs/release.md before install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_SRC="${1:-$ROOT/build/Release/APM44Bridge.driver}"
HAL_DEST="/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
ENTITLEMENTS="$ROOT/Driver/APM44Bridge.entitlements"

if [[ ! -d "$DRIVER_SRC" ]]; then
  echo "error: driver bundle not found: $DRIVER_SRC" >&2
  echo "hint: build Phase 4 HAL target first, or pass path to APM44Bridge.driver" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: missing entitlements: $ENTITLEMENTS" >&2
  exit 1
fi

echo "== Ad-hoc sign (local dev) =="
codesign --force --sign - --timestamp \
  --entitlements "$ENTITLEMENTS" \
  "$DRIVER_SRC"
codesign --verify --deep --verbose=2 "$DRIVER_SRC"

echo "== Install to HAL (sudo) =="
sudo rm -rf "$HAL_DEST"
sudo cp -R "$DRIVER_SRC" "$HAL_DEST"
sudo chown -R root:wheel "$HAL_DEST"

echo "== Reload coreaudiod =="
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod || true

echo "installed: $HAL_DEST"
echo "note: ad-hoc HAL plug-ins may not load on macOS 15+ without Developer ID — see docs/release.md"
