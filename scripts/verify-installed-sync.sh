#!/usr/bin/env bash
# Compare embedded app helper, repo daemon, and live shm-status build IDs.
# Manual Cubase/AirPods steps: .planning/phases/08-hardening-and-live-verification/08-LIVE-VERIFICATION.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: verify-installed-sync.sh [--dry-run] [--help]

Verifies build ID sync between repo daemon, embedded app helper, and shm ring.

Environment:
  APM44_APP_PATH       App bundle (default: build/Release or Debug/APM44 Bridge.app)
  APM44_BRIDGE_BIN     Repo daemon (default: build/BridgeDaemon/apm44-bridge)
  APM44_DRIVER_PATH    HAL driver bundle for optional HAL visibility check

Options:
  --dry-run            Print resolved paths and IDs without requiring a running bridge
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

CONFIG="${APM44_BUILD_CONFIG:-Release}"
APP="${APM44_APP_PATH:-}"
if [[ -z "$APP" ]]; then
  if [[ -d "$ROOT/build/Release/APM44 Bridge.app" ]]; then
    APP="$ROOT/build/Release/APM44 Bridge.app"
  else
    APP="$ROOT/build/Debug/APM44 Bridge.app"
  fi
fi
BRIDGE="${APM44_BRIDGE_BIN:-$ROOT/build/BridgeDaemon/apm44-bridge}"
HELPER="$APP/Contents/MacOS/apm44-bridge"
DRIVER="${APM44_DRIVER_PATH:-/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver}"

parse_build_id() {
  local out="$1"
  if [[ "$out" =~ build=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

parse_shm_helper_id() {
  local out="$1"
  if [[ "$out" =~ helper_build_id=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

parse_shm_driver_id() {
  local out="$1"
  if [[ "$out" =~ driver_build_id=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

parse_shm_status() {
  local out="$1"
  if [[ "$out" =~ shm_status=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

parse_shm_error_code() {
  local out="$1"
  if [[ "$out" =~ error_code=([^[:space:]]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

capture_with_timeout() {
  local seconds="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  "$@" >"$tmp" 2>&1 &
  local pid=$!
  local limit=$((seconds * 10))
  local i
  for ((i = 0; i < limit; ++i)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      local status=$?
      cat "$tmp"
      rm -f "$tmp"
      return "$status"
    fi
    sleep 0.1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  cat "$tmp"
  rm -f "$tmp"
  return 124
}

note() { printf '%s\n' "$*"; }
fail() { note "FAIL: $*"; exit 1; }

note "APM44 installed sync verification"
note "App:    $APP"
note "Repo:   $BRIDGE"
note "Helper: $HELPER"
note "Driver: $DRIVER"
note ""

if [[ ! -x "$BRIDGE" ]]; then
  fail "repo daemon missing at $BRIDGE — cmake --build build --target apm44-bridge"
fi

REPO_VERSION_OUT="$(capture_with_timeout 5 "$BRIDGE" --version || true)"
REPO_ID="$(parse_build_id "$REPO_VERSION_OUT")" || fail "could not parse build= from repo daemon --version"
note "repo_build_id=$REPO_ID"

if [[ ! -x "$HELPER" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    note "WARN: embedded helper missing — run scripts/embed-daemon-in-app.sh after app build"
    note "dry-run: OK (repo ID only)"
    exit 0
  fi
  fail "embedded helper missing at $HELPER — run scripts/embed-daemon-in-app.sh"
fi

HELPER_VERSION_OUT="$(capture_with_timeout 5 "$HELPER" --version || true)"
if ! HELPER_ID="$(parse_build_id "$HELPER_VERSION_OUT")"; then
  if [[ "$DRY_RUN" == "1" ]] && [[ "$(sha256 "$BRIDGE")" == "$(sha256 "$HELPER")" ]]; then
    note "WARN: embedded helper --version unavailable; SHA matches repo daemon"
    HELPER_ID="$REPO_ID"
  else
    fail "could not parse build= from embedded helper --version"
  fi
fi
note "helper_build_id=$HELPER_ID"

if [[ "$REPO_ID" != "$HELPER_ID" ]]; then
  fail "build ID mismatch: repo=$REPO_ID helper=$HELPER_ID"
fi
note "OK: repo and embedded helper match ($REPO_ID)"

if [[ -d "$DRIVER" ]]; then
  DRIVER_PLIST="$DRIVER/Contents/Info.plist"
  if [[ -f "$DRIVER_PLIST" ]]; then
    DRIVER_ID="$(/usr/libexec/PlistBuddy -c 'Print:APM44BuildID' "$DRIVER_PLIST" 2>/dev/null || true)"
    if [[ -n "$DRIVER_ID" ]]; then
      if [[ "$DRIVER_ID" != "$HELPER_ID" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
          note "WARN: installed driver build ID differs (installed=$DRIVER_ID local=$HELPER_ID); live verification requires installing this build"
        else
          fail "build ID mismatch: helper=$HELPER_ID driver=$DRIVER_ID repo=$REPO_ID"
        fi
      fi
      if [[ "$DRIVER_ID" == "$HELPER_ID" ]]; then
        note "OK: installed driver build ID matches helper ($DRIVER_ID)"
      fi
    elif [[ "$DRY_RUN" == "1" ]]; then
      note "WARN: installed driver has no APM44BuildID; install the signed release before live identity verification"
    else
      fail "installed driver build ID missing from $DRIVER_PLIST"
    fi
  elif [[ "$DRY_RUN" == "1" ]]; then
    note "WARN: installed driver Info.plist missing; install the signed release before live identity verification"
  else
    fail "installed driver Info.plist missing at $DRIVER_PLIST"
  fi
elif [[ "$DRY_RUN" == "1" ]]; then
  note "WARN: installed HAL driver not present; install the signed release before live identity verification"
else
  fail "installed HAL driver missing at $DRIVER — install the signed driver bundle before live verification"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  note "dry-run: skipping live --shm-status (no running bridge required)"
  exit 0
fi

SHM_TIMEOUT="${APM44_VERIFY_SHM_TIMEOUT:-5}"
SHM_OUT=""
SHM_STATUS=0
if SHM_OUT="$(capture_with_timeout "$SHM_TIMEOUT" "$BRIDGE" --shm-status)"; then
  SHM_STATUS=0
else
  SHM_STATUS=$?
fi

if [[ -n "$SHM_OUT" ]]; then
  printf '%s\n' "$SHM_OUT"
fi

if [[ "$SHM_STATUS" -eq 124 ]]; then
  fail "live --shm-status timed out after ${SHM_TIMEOUT}s (timeout; helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
fi

if [[ "$SHM_STATUS" -ne 0 ]]; then
  if SHM_ERR="$(parse_shm_error_code "$SHM_OUT")"; then
    fail "live --shm-status failed (exit=$SHM_STATUS error_code=$SHM_ERR helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
  else
    fail "live --shm-status failed (exit=$SHM_STATUS helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
  fi
fi

SHM_STATE=""
if ! SHM_STATE="$(parse_shm_status "$SHM_OUT")"; then
  fail "live --shm-status did not report shm_status=ok (helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
fi
if [[ "$SHM_STATE" != "ok" ]]; then
  if SHM_ERR="$(parse_shm_error_code "$SHM_OUT")"; then
    if [[ "$SHM_ERR" == "open_failed" ]]; then
      fail "live shm ring unavailable (shm_status=$SHM_STATE error_code=open_failed helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
    fi
    fail "live --shm-status reported shm_status=$SHM_STATE (error_code=$SHM_ERR helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
  else
    fail "live --shm-status reported shm_status=$SHM_STATE (helper=$HELPER_ID repo=$REPO_ID); output: $SHM_OUT"
  fi
fi

if ! SHM_HELPER_ID="$(parse_shm_helper_id "$SHM_OUT")"; then
  fail "live --shm-status missing helper_build_id (expected=$HELPER_ID); output: $SHM_OUT"
fi
note "shm_helper_build_id=$SHM_HELPER_ID"
if [[ "$SHM_HELPER_ID" != "$HELPER_ID" ]]; then
  fail "shm-status mismatch: helper=$HELPER_ID shm_helper=$SHM_HELPER_ID repo=$REPO_ID"
fi

if ! SHM_DRIVER_ID="$(parse_shm_driver_id "$SHM_OUT")"; then
  fail "live --shm-status missing driver_build_id (expected=$HELPER_ID); output: $SHM_OUT"
fi
note "shm_driver_build_id=$SHM_DRIVER_ID"
if [[ "$SHM_DRIVER_ID" != "$HELPER_ID" ]]; then
  fail "shm-status mismatch: helper=$HELPER_ID shm_driver=$SHM_DRIVER_ID repo=$REPO_ID"
fi
note "OK: shm-status live sync verified (helper=$HELPER_ID driver=$SHM_DRIVER_ID)"

note "verify-installed-sync: OK"
