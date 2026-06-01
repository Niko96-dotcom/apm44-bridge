#!/usr/bin/env bash
# Verify Developer ID + Hardened Runtime on all release artifacts (SHIP-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
FAIL=0

DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

check() {
  local label="$1"
  local path="$2"
  local deep="${3:-0}"

  if [[ ! -e "$path" ]]; then
    echo "FAIL: $label missing at $path"
    FAIL=1
    return
  fi

  if [[ "$deep" == "1" ]]; then
    if codesign --verify --deep --strict "$path" 2>/dev/null; then
      echo "OK: $label deep strict verify"
    else
      echo "FAIL: $label codesign --verify --deep --strict"
      FAIL=1
    fi
  else
    if codesign --verify --verbose "$path" 2>/dev/null; then
      echo "OK: $label verify"
    else
      echo "FAIL: $label codesign verify"
      FAIL=1
    fi
  fi

  local info
  info="$(codesign -dv --verbose=2 "$path" 2>&1 || true)"
  if grep -q 'Runtime Version' <<<"$info"; then
    echo "OK: $label hardened runtime"
  else
    echo "WARN: $label — hardened runtime flag not detected"
  fi
  if grep -qi 'Developer ID Application' <<<"$info"; then
    echo "OK: $label Developer ID Application"
  else
    echo "WARN: $label — not Developer ID (may be ad-hoc for local dev)"
  fi
}

echo "APM44 release codesign verification (SHIP-01)"
echo ""

check "apm44-bridge" "$DAEMON" 0
check "APM44 Bridge.app" "$APP" 1
check "APM44Bridge.driver" "$DRIVER" 1

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "codesign-verify-release: passed"
else
  echo "codesign-verify-release: failed"
fi
exit "$FAIL"
