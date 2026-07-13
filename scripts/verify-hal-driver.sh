#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"
DAEMON="${APM44_BRIDGE_BIN:-$ROOT/build/BridgeDaemon/apm44-bridge}"
SMOKE="${APM44_HAL_SMOKE_BIN:-$ROOT/build/BridgeDaemon/apm44-hal-smoke}"
FAIL=0

note() { printf '  %s\n' "$*"; }
pass() { note "OK: $*"; }
warn() { note "WARN: $*"; }
fail() { note "FAIL: $*"; FAIL=1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

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
  if strings -a "$BIN" | grep 'com.niko.apm44.bridge.device' >/dev/null; then
    pass "device UID string embedded"
  else
    warn "device UID string not found in binary (check Driver.cpp)"
  fi
fi

if [[ -x "$DAEMON" ]]; then
  pass "bridge helper: $("$DAEMON" --version)"
else
  warn "bridge helper missing at $DAEMON — build target apm44-bridge for shm-status checks"
fi

if xattr -l "$DRIVER" 2>/dev/null | grep -q com.apple.quarantine; then
  warn "quarantine xattr present — run: xattr -d com.apple.quarantine \"$DRIVER\" before install"
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
  INSTALLED_BIN=$(find "$INSTALLED/Contents/MacOS" -maxdepth 1 -type f 2>/dev/null | head -1)
  if [[ -n "$BIN" && -n "$INSTALLED_BIN" ]]; then
    BUILD_SHA="$(sha256 "$BIN")"
    INSTALLED_SHA="$(sha256 "$INSTALLED_BIN")"
    if [[ "$BUILD_SHA" == "$INSTALLED_SHA" ]]; then
      pass "installed HAL executable matches build ($BUILD_SHA)"
    elif [[ "${APM44_ALLOW_STALE_INSTALLED:-0}" == "1" ]]; then
      warn "installed HAL executable differs from build (build=$BUILD_SHA installed=$INSTALLED_SHA)"
    else
      fail "installed HAL executable differs from build (build=$BUILD_SHA installed=$INSTALLED_SHA)"
    fi
  else
    warn "could not compare build and installed HAL executables"
  fi

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

if [[ -x "$DAEMON" ]] && system_profiler SPAudioDataType 2>/dev/null | grep -qi 'APM44 Bridge'; then
  SHM_OUT="$("$DAEMON" --shm-status 2>&1 || true)"
  HELPER_ID="$(printf '%s\n' "$SHM_OUT" | awk -F= '/^helper_build_id=/{print $2; exit}')"
  DRIVER_ID="$(printf '%s\n' "$SHM_OUT" | awk -F= '/^driver_build_id=/{print $2; exit}')"
  if [[ -n "$HELPER_ID" && -n "$DRIVER_ID" ]]; then
    if [[ "$HELPER_ID" == "$DRIVER_ID" ]]; then
      pass "helper and live ring build IDs match ($HELPER_ID)"
    else
      fail "helper and live ring producer build IDs differ (helper=$HELPER_ID ring=$DRIVER_ID)"
    fi
  else
    warn "could not parse --shm-status build IDs (ring may be absent)"
  fi
elif [[ -x "$DAEMON" ]]; then
  warn "skipping --shm-status build ID check (APM44 Bridge not visible)"
fi

if [[ "${APM44_SKIP_HAL_SMOKE:-0}" != "1" ]]; then
  if [[ -x "$SMOKE" ]]; then
    if system_profiler SPAudioDataType 2>/dev/null | grep -qi 'APM44 Bridge'; then
      SMOKE_OUT="$("$SMOKE" --timeout-sec "${APM44_HAL_SMOKE_TIMEOUT:-5}" 2>&1)" || {
        fail "HAL smoke could not start APM44 Bridge / open shm"
        while IFS= read -r line; do note "  $line"; done <<<"$SMOKE_OUT"
      }
      if [[ "${SMOKE_OUT+x}" == "x" ]] && grep -q '^hal_smoke=ok' <<<"$SMOKE_OUT"; then
        pass "HAL smoke opened APM44 shm ring"
        while IFS= read -r line; do note "  $line"; done <<<"$SMOKE_OUT"
      fi
    else
      warn "skipping HAL smoke because APM44 Bridge is not visible"
    fi
  else
    warn "HAL smoke tool missing at $SMOKE — build target apm44-hal-smoke"
  fi
fi

if [[ -n "$BIN" ]]; then
  CS_INFO="$(codesign -dv --verbose=2 "$BIN" 2>&1 || true)"
  if grep -qi 'Developer ID Application' <<<"$CS_INFO"; then
    pass "executable signed with Developer ID Application"
  else
    warn "executable not Developer ID signed — run scripts/sign-release.sh before production install"
  fi
  if grep -q 'Runtime Version' <<<"$CS_INFO" || grep -Eq 'flags=.*runtime' <<<"$CS_INFO"; then
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
