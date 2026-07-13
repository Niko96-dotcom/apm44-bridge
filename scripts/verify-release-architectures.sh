#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"
DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
HELPER="${APM44_HELPER_PATH:-$APP/Contents/MacOS/apm44-bridge}"
DRIVER="${APM44_DRIVER_EXECUTABLE:-$ROOT/build/Driver/APM44Bridge.driver/Contents/MacOS/APM44Bridge}"
APP_EXECUTABLE="${APM44_APP_EXECUTABLE:-$APP/Contents/MacOS/APM44 Bridge}"

fail() { echo "error: $*" >&2; exit 1; }

check_universal() {
  local label="$1"
  local path="$2"
  [[ -f "$path" ]] || fail "$label missing at $path"
  local arches
  arches="$(lipo -archs "$path" 2>/dev/null)" || fail "could not inspect $label architectures"
  for expected in arm64 x86_64; do
    [[ " $arches " == *" $expected "* ]] ||
      fail "$label lacks $expected (found: $arches)"
  done
  echo "OK: $label architectures=$arches"
}

check_universal "app executable" "$APP_EXECUTABLE"
check_universal "embedded helper" "$HELPER"
check_universal "standalone daemon" "$DAEMON"
check_universal "HAL driver" "$DRIVER"
echo "verify-release-architectures: OK"
