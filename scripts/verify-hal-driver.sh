#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
FAIL=0

note() { printf '  %s\n' "$*"; }
pass() { note "OK: $*"; }
warn() { note "WARN: $*"; }
fail() { note "FAIL: $*"; FAIL=1; }

echo "APM44 HAL driver verification"
echo "Bundle: $DRIVER"
echo ""

if [[ ! -d "$DRIVER" ]]; then
  fail "bundle missing — run: cmake --build build --target APM44Bridge"
  exit "$FAIL"
fi
pass "bundle directory exists"

PLIST="$DRIVER/Contents/Info.plist"
if [[ ! -f "$PLIST" ]]; then
  fail "Info.plist missing"
else
  pass "Info.plist present"
  if /usr/libexec/PlistBuddy -c 'Print :CFPlugInFactories' "$PLIST" >/dev/null 2>&1; then
    pass "CFPlugInFactories present"
  else
    fail "CFPlugInFactories missing"
  fi
fi

BIN=$(find "$DRIVER/Contents/MacOS" -maxdepth 1 -type f 2>/dev/null | head -1)
if [[ -z "$BIN" ]]; then
  fail "MacOS executable missing"
else
  pass "executable: $(basename "$BIN")"
  if strings "$BIN" | grep -q 'com.niko.apm44.bridge.device'; then
    pass "device UID string embedded"
  else
    warn "device UID string not found in binary (check Driver.cpp)"
  fi
fi

if system_profiler SPAudioDataType 2>/dev/null | grep -qi 'APM44 Bridge'; then
  pass "system_profiler lists APM44 Bridge"
else
  warn "APM44 Bridge not visible (driver may be unsigned or coreaudiod not reloaded)"
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "verify-hal-driver: structural checks passed"
else
  echo "verify-hal-driver: failed"
fi
exit "$FAIL"
