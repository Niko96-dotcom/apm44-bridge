#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_SRC="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
HAL_DIR="/Library/Audio/Plug-Ins/HAL"

if [[ ! -d "$DRIVER_SRC" ]]; then
  echo "error: driver bundle not found at $DRIVER_SRC" >&2
  echo "Build first: cmake -S . -B build && cmake --build build --target APM44Bridge" >&2
  exit 1
fi

echo "Installing $DRIVER_SRC -> $HAL_DIR/APM44Bridge.driver"
sudo mkdir -p "$HAL_DIR"
sudo rm -rf "$HAL_DIR/APM44Bridge.driver"
sudo cp -R "$DRIVER_SRC" "$HAL_DIR/APM44Bridge.driver"
sudo chown -R root:wheel "$HAL_DIR/APM44Bridge.driver"

echo ""
echo "Reload Core Audio (may require password):"
echo "  sudo launchctl kickstart -k system/com.apple.audio.coreaudiod"
echo ""
echo "If the device does not appear, log out/in or reboot once (first HAL install)."
echo "Unsigned dev builds may be blocked on macOS 15+ until Developer ID signing (Phase 5)."
