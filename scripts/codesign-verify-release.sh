#!/usr/bin/env bash
# Verify Developer ID + Hardened Runtime on all release artifacts (SHIP-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
FAIL=0
ALLOW_LOCAL_CODESIGN="${APM44_ALLOW_LOCAL_CODESIGN:-0}"

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
  if grep -q 'Runtime Version' <<<"$info" || grep -Eq 'flags=.*runtime' <<<"$info"; then
    echo "OK: $label hardened runtime"
  elif [[ "$ALLOW_LOCAL_CODESIGN" == "1" ]]; then
    echo "WARN: $label — hardened runtime flag not detected (APM44_ALLOW_LOCAL_CODESIGN=1)"
  else
    echo "FAIL: $label — hardened runtime flag not detected"
    FAIL=1
  fi
  if grep -qi 'Developer ID Application' <<<"$info"; then
    echo "OK: $label Developer ID Application"
  elif [[ "$ALLOW_LOCAL_CODESIGN" == "1" ]]; then
    echo "WARN: $label — not Developer ID (APM44_ALLOW_LOCAL_CODESIGN=1)"
  else
    echo "FAIL: $label — not Developer ID Application"
    FAIL=1
  fi

  check_release_entitlements "$label" "$path"
}

check_release_entitlements() {
  local label="$1"
  local target="$2"
  local tmp
  tmp="$(mktemp)"
  # codesign writes this file only when an entitlements blob is present.
  codesign -d --entitlements "$tmp" --xml "$target" >/dev/null 2>&1 || true
  if [[ ! -s "$tmp" ]]; then
    echo "OK: $label unsandboxed (no entitlements blob)"
    rm -f "$tmp"
    return
  fi

  local sandbox task_allow
  # PlistBuddy treats dotted entitlement names as a single key; plutil -extract
  # would split them on '.' and miss App Sandbox / get-task-allow.
  sandbox="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$tmp" 2>/dev/null || true)"
  task_allow="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"

  if [[ "$sandbox" == "true" ]]; then
    echo "FAIL: $label enables App Sandbox"
    FAIL=1
  else
    echo "OK: $label App Sandbox not enabled"
  fi
  if [[ "$task_allow" == "true" ]]; then
    echo "FAIL: $label has get-task-allow (not a release signature)"
    FAIL=1
  else
    echo "OK: $label has no get-task-allow"
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
