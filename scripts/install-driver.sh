#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_SRC="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
HAL_DIR="/Library/Audio/Plug-Ins/HAL"
RELOAD_COREAUDIO="${APM44_RELOAD_COREAUDIO:-1}"
VERIFY_AFTER_INSTALL="${APM44_VERIFY_AFTER_INSTALL:-1}"

if [[ "${1:-}" == "--no-reload" ]]; then
  RELOAD_COREAUDIO=0
fi

if [[ ! -d "$DRIVER_SRC" ]]; then
  echo "error: driver bundle not found at $DRIVER_SRC" >&2
  echo "Build first: cmake -S . -B build && cmake --build build --target APM44Bridge apm44-hal-smoke" >&2
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

SRC_BIN="$(find "$DRIVER_SRC/Contents/MacOS" -maxdepth 1 -type f 2>/dev/null | head -1)"
DST_BIN="$(find "$HAL_DIR/APM44Bridge.driver/Contents/MacOS" -maxdepth 1 -type f 2>/dev/null | head -1)"
if [[ -z "$SRC_BIN" || -z "$DST_BIN" ]]; then
  echo "error: could not find source or installed driver executable for verification" >&2
  exit 1
fi
SRC_SHA="$(shasum -a 256 "$SRC_BIN" | awk '{print $1}')"
DST_SHA="$(shasum -a 256 "$DST_BIN" | awk '{print $1}')"
if [[ "$SRC_SHA" != "$DST_SHA" ]]; then
  echo "error: installed driver does not match source driver" >&2
  echo "  source:    $SRC_SHA $SRC_BIN" >&2
  echo "  installed: $DST_SHA $DST_BIN" >&2
  exit 1
fi
echo "OK: installed driver executable matches build ($SRC_SHA)"

if [[ "$RELOAD_COREAUDIO" == "1" ]]; then
  echo "Reloading Core Audio (coreaudiod will respawn)..."
  if sudo killall coreaudiod 2>/dev/null; then
    sleep 2
    if pgrep -x coreaudiod >/dev/null 2>&1; then
      echo "OK: coreaudiod is running again."
    else
      echo "warn: coreaudiod not seen yet — wait a few seconds or reboot once." >&2
    fi
  else
    echo "warn: could not reload coreaudiod; reboot once to load the new HAL driver." >&2
  fi
fi

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
if [[ "$VERIFY_AFTER_INSTALL" == "1" ]]; then
  echo "Verifying installed HAL driver..."
  bash "$ROOT/scripts/verify-hal-driver.sh"
else
  echo "Verify installed HAL driver:"
  echo "  bash scripts/verify-hal-driver.sh"
fi
