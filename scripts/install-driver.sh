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

# Avoid propagating quarantine from Downloads/build tree into HAL.
xattr -cr "$DRIVER_SRC" 2>/dev/null || true

# Root cannot read ~/Documents on many macOS versions without Full Disk Access — stage in /tmp.
STAGE="${TMPDIR:-/tmp}/APM44Bridge.driver"
rm -rf "$STAGE"
ditto "$DRIVER_SRC" "$STAGE"

echo "Installing $DRIVER_SRC -> $HAL_DIR/APM44Bridge.driver (via $STAGE)"
sudo mkdir -p "$HAL_DIR"
sudo rm -rf "$HAL_DIR/APM44Bridge.driver"
# ditto preserves extended attributes (e.g. stapled notarization ticket).
sudo ditto "$STAGE" "$HAL_DIR/APM44Bridge.driver"
rm -rf "$STAGE"
sudo chown -R root:wheel "$HAL_DIR/APM44Bridge.driver"
sudo xattr -cr "$HAL_DIR/APM44Bridge.driver" 2>/dev/null || true

echo ""
if spctl -a -vv -t install "$DRIVER_SRC" 2>&1 | grep -q 'accepted'; then
  echo "Gatekeeper: driver is accepted for load."
else
  echo "WARNING: Gatekeeper does not accept this driver yet."
  echo "  Signed-but-unnotarized Developer ID builds are rejected on macOS 15+"
  echo "  and will NOT appear in Audio MIDI Setup until notarized + stapled:"
  echo "    bash scripts/notarize-hal-driver.sh   # needs NOTARY_PROFILE / AC_NOTARY"
  echo "  See docs/release.md"
fi

echo ""
echo "Reload Core Audio (required after install):"
echo "  bash scripts/reload-coreaudio.sh"
echo "  # or: sudo killall coreaudiod"
echo ""
echo "Note: launchctl kickstart for coreaudiod is blocked on macOS 14.4+ (SIP error 150)."
echo "If the device does not appear, reboot once (first HAL install)."
