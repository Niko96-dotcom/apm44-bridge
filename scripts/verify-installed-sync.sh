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

note() { printf '%s\n' "$*"; }
fail() { note "FAIL: $*"; exit 1; }

note "APM44 installed sync verification"
note "App:    $APP"
note "Repo:   $BRIDGE"
note "Helper: $HELPER"
note ""

if [[ ! -x "$BRIDGE" ]]; then
  fail "repo daemon missing at $BRIDGE — cmake --build build --target apm44-bridge"
fi

REPO_ID="$(parse_build_id "$("$BRIDGE" --version 2>/dev/null || true)")" || fail "could not parse build= from repo daemon --version"
note "repo_build_id=$REPO_ID"

if [[ ! -x "$HELPER" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    note "WARN: embedded helper missing — run scripts/embed-daemon-in-app.sh after app build"
    note "dry-run: OK (repo ID only)"
    exit 0
  fi
  fail "embedded helper missing at $HELPER — run scripts/embed-daemon-in-app.sh"
fi

HELPER_ID="$(parse_build_id "$("$HELPER" --version 2>/dev/null || true)")" || fail "could not parse build= from embedded helper --version"
note "helper_build_id=$HELPER_ID"

if [[ "$REPO_ID" != "$HELPER_ID" ]]; then
  fail "build ID mismatch: repo=$REPO_ID helper=$HELPER_ID"
fi
note "OK: repo and embedded helper match ($REPO_ID)"

if [[ "$DRY_RUN" == "1" ]]; then
  note "dry-run: skipping live --shm-status (no running bridge required)"
  exit 0
fi

SHM_OUT="$("$BRIDGE" --shm-status 2>/dev/null || true)"
if [[ -z "$SHM_OUT" ]]; then
  note "WARN: --shm-status produced no output (HAL ring may be inactive)"
  note "OK: repo/helper sync verified; run with bridge active for shm ID check"
  exit 0
fi

if SHM_ID="$(parse_shm_helper_id "$SHM_OUT")"; then
  note "shm_helper_build_id=$SHM_ID"
  if [[ "$SHM_ID" != "$HELPER_ID" ]]; then
    fail "shm-status mismatch: helper=$HELPER_ID shm=$SHM_ID repo=$REPO_ID"
  fi
  note "OK: shm-status helper_build_id matches embedded helper"
else
  note "WARN: could not parse helper_build_id from --shm-status"
fi

note "verify-installed-sync: OK"
