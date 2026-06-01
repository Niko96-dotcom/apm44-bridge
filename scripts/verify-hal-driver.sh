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

if xattr -l "$DRIVER" 2>/dev/null | grep -q com.apple.quarantine; then
  warn "quarantine xattr present — run: xattr -cr \"$DRIVER\" before install"
else
  pass "no quarantine xattr on bundle"
fi

SPCTL_OUT="$(spctl -a -vv -t install "$DRIVER" 2>&1 || true)"
if grep -q 'accepted' <<<"$SPCTL_OUT"; then
  pass "Gatekeeper accepts driver (signed + notarized/stapled)"
elif grep -qi 'Unnotarized' <<<"$SPCTL_OUT"; then
  warn "Developer ID signed but NOT notarized — macOS 15+ will not load HAL (run scripts/notarize-hal-driver.sh)"
else
  warn "Gatekeeper does not accept driver — check codesign / notarization"
fi

INSTALLED="/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"
if [[ -d "$INSTALLED" ]]; then
  INST_OUT="$(spctl -a -vv -t install "$INSTALLED" 2>&1 || true)"
  if grep -q 'accepted' <<<"$INST_OUT"; then
    pass "installed HAL copy is Gatekeeper-accepted"
  elif grep -qi 'Unnotarized' <<<"$INST_OUT"; then
    warn "installed HAL is signed but not notarized — reinstall after notarize-hal-driver.sh"
  else
    warn "installed HAL at $INSTALLED is not Gatekeeper-accepted"
  fi
fi

if system_profiler SPAudioDataType 2>/dev/null | grep -qi 'APM44 Bridge'; then
  pass "system_profiler lists APM44 Bridge"
else
  warn "APM44 Bridge not visible (notarize+staple, reinstall, reload-coreaudio.sh, or reboot)"
fi

if [[ -n "$BIN" ]]; then
  CS_INFO="$(codesign -dv --verbose=2 "$BIN" 2>&1 || true)"
  if grep -qi 'Developer ID Application' <<<"$CS_INFO"; then
    pass "executable signed with Developer ID Application"
  else
    warn "executable not Developer ID signed — run scripts/sign-release.sh before production install"
  fi
  if grep -q 'Runtime Version' <<<"$CS_INFO"; then
    pass "executable has Hardened Runtime"
  else
    warn "Hardened Runtime not detected on executable"
  fi
fi

if [[ -d "$INSTALLED" ]]; then
  if pgrep -x coreaudiod >/dev/null 2>&1; then
    pass "coreaudiod is running"
  else
    warn "coreaudiod not running"
  fi
fi

echo ""
echo "Release signing: scripts/sign-release.sh"
echo "Notarize driver: scripts/notarize-hal-driver.sh"
echo "Full release zip: scripts/notary-dry-run.sh"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "verify-hal-driver: structural checks passed"
else
  echo "verify-hal-driver: failed"
fi
exit "$FAIL"
