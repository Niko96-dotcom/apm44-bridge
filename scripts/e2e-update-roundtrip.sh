#!/usr/bin/env bash
# One-command installed-update round trip for APM44 Bridge.
# Updates the REAL installed app via a local signed Sparkle feed and prints an
# unambiguous PASS/FAIL table. Never uses sudo, never handles passwords.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: e2e-update-roundtrip.sh --pkg <candidate.pkg> --expect-version <v> [--label <v>] [--start-bridge] [--port 8765] [--auth-timeout 900] [--yes]

The ONE command for a complete installed-update round trip. It updates the
REAL installed app, so without --yes it prints what it will do and asks for
confirmation. Default label is expect-version.

Steps:
  1 Preflight, 2 local feed+server, 3 quit+relaunch, 4 bridge before update
  (with --start-bridge), 5 wait for update available, 6 click Install Update,
  7 admin approval + Install and Relaunch, 8 new PID + version + settle,
  9 checks, 10 summary. Exit 0 only if every check passed.
USAGE
}

PKG=""
EXPECT_VERSION=""
LABEL=""
START_BRIDGE=0
PORT="8765"
AUTH_TIMEOUT="900"
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --pkg)
      PKG="${2:-}"
      shift 2
      ;;
    --expect-version)
      EXPECT_VERSION="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --start-bridge)
      START_BRIDGE=1
      shift
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --auth-timeout)
      AUTH_TIMEOUT="${2:-}"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PKG" ]]; then
  echo "error: --pkg is required" >&2
  usage >&2
  exit 2
fi
if [[ -z "$EXPECT_VERSION" ]]; then
  echo "error: --expect-version is required" >&2
  usage >&2
  exit 2
fi
if [[ -z "$LABEL" ]]; then
  LABEL="$EXPECT_VERSION"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${APM44_E2E_APP_PATH:-/Applications/APM44 Bridge.app}"
DRIVER_PATH="${APM44_E2E_DRIVER_PATH:-/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver}"
HELPER_DEFAULT="$APP_PATH/Contents/MacOS/apm44-bridge"
HELPER="${APM44_E2E_HELPER:-$HELPER_DEFAULT}"
BUNDLE_ID="${APM44_E2E_BUNDLE_ID:-com.niko.apm44.menu}"
OSASCRIPT="${APM44_E2E_OSASCRIPT:-osascript}"
OPEN_CMD="${APM44_E2E_OPEN:-open}"
PGREP="${APM44_E2E_PGREP:-pgrep}"
PKILL="${APM44_E2E_PKILL:-pkill}"
LOG_CMD="${APM44_E2E_LOG:-log}"
DEFAULTS="${APM44_E2E_DEFAULTS:-defaults}"
CURL="${APM44_E2E_CURL:-curl}"
PYTHON3="${APM44_E2E_PYTHON3:-python3}"
PLISTBUDDY="${APM44_E2E_PLISTBUDDY:-/usr/libexec/PlistBuddy}"
FEED_SCRIPT="${APM44_E2E_FEED_SCRIPT:-$SCRIPT_DIR/e2e-local-update-feed.sh}"
AUDIO_FLOW_SCRIPT="${APM44_E2E_AUDIO_FLOW_SCRIPT:-$SCRIPT_DIR/e2e-check-audio-flow.sh}"
SETTLE_SECONDS="${APM44_E2E_SETTLE_SECONDS:-25}"
POLL="${APM44_E2E_POLL_INTERVAL:-1}"
BRIDGE_WAIT="${APM44_E2E_BRIDGE_WAIT:-60}"
UPDATE_WAIT="${APM44_E2E_UPDATE_WAIT:-120}"
INSTALL_BTN_WAIT="${APM44_E2E_INSTALL_BUTTON_WAIT:-60}"
NEW_PID_WAIT="${APM44_E2E_NEW_PID_WAIT:-180}"
FEED_WAIT="${APM44_E2E_FEED_WAIT:-30}"
QUIT_WAIT="${APM44_E2E_QUIT_WAIT:-20}"

APP_EXEC="$APP_PATH/Contents/MacOS/APM44 Bridge"
APP_PROC_PATTERN="^${APP_EXEC}( |\$)"
APP_INFO="$APP_PATH/Contents/Info.plist"
DRIVER_INFO="$DRIVER_PATH/Contents/Info.plist"
FEED_URL="http://127.0.0.1:${PORT}/appcast.xml"

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo "This will update the REAL installed app at:"
  echo "  $APP_PATH"
  echo "using candidate pkg:"
  echo "  $PKG"
  echo "expecting version $EXPECT_VERSION (feed label $LABEL) via $FEED_URL"
  if [[ "$START_BRIDGE" -eq 1 ]]; then
    echo "bridge audio flow will also be verified (--start-bridge)"
  fi
  echo "It will quit and relaunch the app and needs ONE admin approval in macOS UI."
  printf 'Proceed? [y/N] '
  read -r REPLY_ANS || REPLY_ANS=""
  case "$REPLY_ANS" in
    y|Y|yes|YES|Yes)
      ;;
    *)
      echo "aborted."
      exit 1
      ;;
  esac
fi

RUN_DIR="$(mktemp -d)"
echo "run dir: $RUN_DIR"
SERVER_PID=""
cleanup() {
  # Never leave the app pointed at the test feed: if it still runs with our
  # -SUFeedURL (e.g. after a FAIL before the update), relaunch it normally.
  if "$PGREP" -f "SUFeedURL http://127.0.0.1:${PORT}/appcast.xml" >/dev/null 2>&1; then
    "$OSASCRIPT" -e 'tell application id "com.niko.apm44.menu" to quit' >/dev/null 2>&1 || true
    local waited=0
    while "$PGREP" -f "SUFeedURL http://127.0.0.1:${PORT}/appcast.xml" >/dev/null 2>&1 && [[ "$waited" -lt 20 ]]; do
      sleep 0.5
      waited=$((waited + 1))
    done
    "$OPEN_CMD" -a "$APP_PATH" >/dev/null 2>&1 || true
    echo "cleanup: relaunched APM44 Bridge without test arguments"
  fi
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -f "$RUN_DIR/server.pid" ]]; then
    SPID="$(cat "$RUN_DIR/server.pid" 2>/dev/null || echo "")"
    if [[ -n "$SPID" ]]; then
      kill "$SPID" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

e2e_app_pids() {
  # Match with or without launch arguments (a relaunch for this test adds them).
  "$PGREP" -f "$APP_PROC_PATTERN" 2>/dev/null || true
}

e2e_app_version_now() {
  "$PLISTBUDDY" -c "Print :CFBundleShortVersionString" "$APP_INFO" 2>/dev/null || echo "unknown"
}

e2e_log_updates() {
  "$LOG_CMD" show --start "$RUN_LOG_START" --info --style compact --predicate 'process == "APM44 Bridge" AND category == "Updates"' 2>/dev/null || true
}

e2e_log_bridge() {
  "$LOG_CMD" show --start "$RUN_LOG_START" --info --style compact --predicate 'process == "APM44 Bridge" AND category == "Bridge"' 2>/dev/null || true
}

e2e_resolve_sign_update() {
  if [[ -n "${SPARKLE_SIGN_UPDATE:-}" ]]; then
    printf '%s\n' "$SPARKLE_SIGN_UPDATE"
    return 0
  fi
  bash "$SCRIPT_DIR/ensure-sparkle-tools.sh"
}

# STEP 1: Preflight
echo "STEP 1: Preflight"
if [[ ! -d "$APP_PATH" ]]; then
  echo "FAIL: installed app missing at $APP_PATH" >&2
  exit 1
fi
if [[ ! -f "$PKG" ]]; then
  echo "FAIL: candidate pkg missing at $PKG" >&2
  exit 1
fi
if "$CURL" -sf --connect-timeout 2 "http://127.0.0.1:${PORT}/appcast.xml" >/dev/null 2>&1; then
  echo "FAIL: port $PORT is already in use" >&2
  exit 1
fi
SIGN_UPDATE_BIN="$(e2e_resolve_sign_update || true)"
if [[ -z "$SIGN_UPDATE_BIN" || ! -x "$SIGN_UPDATE_BIN" ]]; then
  echo "FAIL: sign_update is not available (${SIGN_UPDATE_BIN:-<empty>})" >&2
  exit 1
fi
if ! "$OSASCRIPT" -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
  echo "FAIL: osascript accessibility check failed" >&2
  echo "hint: grant Accessibility to your terminal: System Settings > Privacy & Security > Accessibility, add Terminal (and APM44 Bridge), then re-run." >&2
  exit 1
fi
OLD_VERSION="$(e2e_app_version_now)"
OLD_BUILD="$("$PLISTBUDDY" -c "Print :APM44BuildID" "$APP_INFO" 2>/dev/null || echo "unknown")"
OLD_PID="$(e2e_app_pids | head -n 1 | tr -d '[:space:]' || true)"
if [[ -z "$OLD_PID" ]]; then
  OLD_PID="none"
fi
echo "preflight: version=$OLD_VERSION build=$OLD_BUILD pid=$OLD_PID port=$PORT"
# Launch-argument automation hooks exist from 0.12.15. An older installed app
# still offers the update through its own launch check (0.12.11+), but cannot
# start the bridge on request, so the resume and audio checks become NOT RUN.
HOOKS_MIN_VERSION="0.12.15"
e2e_version_ge() {
  local IFS=.
  local -a a=($1) b=($2)
  local i x y
  for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 1
    ((10#$x > 10#$y)) && return 0
    ((10#$x < 10#$y)) && return 1
  done
  return 0
}
START_BRIDGE_NOT_RUN_REASON=""
if [[ "$START_BRIDGE" -eq 1 ]] && ! e2e_version_ge "$OLD_VERSION" "$HOOKS_MIN_VERSION"; then
  START_BRIDGE_NOT_RUN_REASON="installed $OLD_VERSION predates the automation hooks ($HOOKS_MIN_VERSION+)"
  echo "note: --start-bridge ignored: $START_BRIDGE_NOT_RUN_REASON; bridge resume and audio checks will be NOT RUN"
  START_BRIDGE=0
fi
if [[ "$START_BRIDGE" -eq 1 ]]; then
  # The app refuses to start without its selected output, so check it here
  # instead of timing out later with a vague "helper did not appear".
  OUTPUT_UID="$("$DEFAULTS" read com.niko.apm44.menu apm44.outputDeviceUid 2>/dev/null || true)"
  if [[ -z "$OUTPUT_UID" ]]; then
    echo "FAIL: no output device is selected in APM44 Bridge; select one in the app or omit --start-bridge" >&2
    exit 1
  fi
  if ! "$HELPER" --list-devices 2>/dev/null | awk -F'\t' -v uid="$OUTPUT_UID" '$1 == uid && $5 == 1 { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "FAIL: the selected output ($OUTPUT_UID) is not connected; connect and wake it (for AirPods Max: plug in USB-C and put them on) or omit --start-bridge" >&2
    exit 1
  fi
  echo "preflight: selected output connected ($OUTPUT_UID)"
fi
echo "STEP 1: OK"

# STEP 2: Local feed and server
echo "STEP 2: Local feed and server"
FEED_DIR="$RUN_DIR/feed"
mkdir -p "$FEED_DIR"
bash "$FEED_SCRIPT" --pkg "$PKG" --version "$LABEL" --out "$FEED_DIR" --port "$PORT"
# exec so $! is the server itself; killing a wrapper subshell would orphan it.
( cd "$FEED_DIR" && exec "$PYTHON3" -m http.server "$PORT" --bind 127.0.0.1 >"$RUN_DIR/server.log" 2>&1 ) &
SERVER_PID=$!
printf '%s\n' "$SERVER_PID" >"$RUN_DIR/server.pid"
FEED_OK=0
FEED_START="$(date +%s)"
while true; do
  if "$CURL" -sf "http://127.0.0.1:${PORT}/appcast.xml" -o /dev/null >/dev/null 2>&1; then
    FEED_OK=1
    break
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - FEED_START)) -ge "$FEED_WAIT" ]]; then
    break
  fi
  sleep "$POLL"
done
if [[ "$FEED_OK" -ne 1 ]]; then
  echo "FAIL: local feed did not serve HTTP 200 within ${FEED_WAIT}s" >&2
  exit 1
fi
echo "STEP 2: OK (feed at $FEED_URL)"

# STEP 3: Quit and relaunch
echo "STEP 3: Quit and relaunch"
RUN_LOG_START="$(date '+%Y-%m-%d %H:%M:%S')"
"$OSASCRIPT" -e 'tell application "APM44 Bridge" to quit' >/dev/null 2>&1 || true
QUIT_START="$(date +%s)"
QUIT_DONE=0
while true; do
  LEFT="$(e2e_app_pids || true)"
  if [[ -z "$LEFT" ]]; then
    QUIT_DONE=1
    break
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - QUIT_START)) -ge "$QUIT_WAIT" ]]; then
    break
  fi
  sleep "$POLL"
done
if [[ "$QUIT_DONE" -ne 1 ]]; then
  "$PKILL" -TERM -f "$APP_PROC_PATTERN" 2>/dev/null || true
  sleep "$POLL"
  LEFT2="$(e2e_app_pids || true)"
  if [[ -n "$LEFT2" ]]; then
    echo "FAIL: app did not quit (pids: $LEFT2)" >&2
    exit 1
  fi
fi
if [[ "$START_BRIDGE" -eq 1 ]]; then
  "$OPEN_CMD" -a "$APP_PATH" --args -AppleLanguages '(en)' -AppleLocale en_US -SUFeedURL "$FEED_URL" -APM44AutomationCheckForUpdates YES -APM44AutomationStartBridge YES >/dev/null 2>&1
else
  "$OPEN_CMD" -a "$APP_PATH" --args -AppleLanguages '(en)' -AppleLocale en_US -SUFeedURL "$FEED_URL" -APM44AutomationCheckForUpdates YES >/dev/null 2>&1
fi
echo "STEP 3: OK (relaunched with feed $FEED_URL)"

# STEP 4: Bridge running before update
BRIDGE_WAS_RUNNING=0
echo "STEP 4: Bridge running before update"
if [[ "$START_BRIDGE" -eq 1 ]]; then
  B_START="$(date +%s)"
  while true; do
    if "$PGREP" -f "apm44-bridge --virtual-device" >/dev/null 2>&1; then
      BRIDGE_WAS_RUNNING=1
      break
    fi
    NOW="$(date +%s)"
    if [[ $((NOW - B_START)) -ge "$BRIDGE_WAIT" ]]; then
      break
    fi
    sleep "$POLL"
  done
  if [[ "$BRIDGE_WAS_RUNNING" -ne 1 ]]; then
    echo "FAIL: bridge helper (--virtual-device) did not appear within ${BRIDGE_WAIT}s" >&2
    exit 1
  fi
  echo "STEP 4: OK (bridge was running)"
elif [[ -n "$START_BRIDGE_NOT_RUN_REASON" ]]; then
  echo "STEP 4: NOT RUN ($START_BRIDGE_NOT_RUN_REASON)"
else
  echo "STEP 4: SKIPPED (no --start-bridge)"
fi

# STEP 5: Wait for update available
echo "STEP 5: Wait for update available"
U_START="$(date +%s)"
U_FOUND=0
while true; do
  if e2e_log_updates 2>/dev/null | grep -Fq "Update available version=${LABEL}"; then
    U_FOUND=1
    break
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - U_START)) -ge "$UPDATE_WAIT" ]]; then
    break
  fi
  sleep "$POLL"
done
if [[ "$U_FOUND" -ne 1 ]]; then
  echo "FAIL: did not see 'Update available version=${LABEL}' within ${UPDATE_WAIT}s" >&2
  exit 1
fi
FEED_PIDS="$(e2e_app_pids || true)"
if [[ -z "$FEED_PIDS" ]]; then
  echo "FAIL: no feed process found after relaunch (old=$OLD_PID)" >&2
  exit 1
fi
echo "STEP 5: OK (update available ${LABEL})"

# STEP 6: Click Install Update
echo "STEP 6: Click Install Update"
I_START="$(date +%s)"
I_CLICKED=0
INSTALL_APPLESCRIPT='tell application "System Events"
  tell process "APM44 Bridge"
    repeat with w in every window
      repeat with bref in {"Install Update", "Installieren"}
        set bname to contents of bref
        if exists button bname of w then
          try
            click button bname of w
          end try
          -- Clicking closes the window, which can make the click call itself
          -- report an error; the button existed, so count it as clicked.
          return "clicked:" & bname
        end if
      end repeat
    end repeat
    error "no install button yet"
  end tell
end tell'
while true; do
  if "$OSASCRIPT" -e "$INSTALL_APPLESCRIPT" >/dev/null 2>&1; then
    I_CLICKED=1
    break
  fi
  # The app log is the authority: a started download means Install was clicked.
  if e2e_log_updates | grep -Fq "Update downloaded version=${LABEL}"; then
    I_CLICKED=1
    break
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - I_START)) -ge "$INSTALL_BTN_WAIT" ]]; then
    break
  fi
  sleep "$POLL"
done
if [[ "$I_CLICKED" -ne 1 ]]; then
  echo "FAIL: Install Update button not found/clicked within ${INSTALL_BTN_WAIT}s" >&2
  exit 1
fi
echo "STEP 6: OK (clicked Install Update)"

# STEP 7: Admin approval and Install and Relaunch
echo "=============================================="
echo "ACTION REQUIRED: approve the macOS admin prompt (Touch ID or password) for APM44 Bridge"
echo "=============================================="
echo "STEP 7: Wait for Install and Relaunch"
A_START="$(date +%s)"
A_CLICKED=0
RELAUNCH_APPLESCRIPT='tell application "System Events"
  tell process "APM44 Bridge"
    repeat with w in every window
      repeat with bref in {"Install and Relaunch", "Installieren und App neu starten"}
        set bname to contents of bref
        if exists button bname of w then
          try
            click button bname of w
          end try
          -- Clicking closes the window, which can make the click call itself
          -- report an error; the button existed, so count it as clicked.
          return "clicked:" & bname
        end if
      end repeat
    end repeat
    error "no relaunch button yet"
  end tell
end tell'
while true; do
  if "$OSASCRIPT" -e "$RELAUNCH_APPLESCRIPT" >/dev/null 2>&1; then
    A_CLICKED=1
    break
  fi
  # Someone (the script or the human) already clicked Install and Relaunch.
  if e2e_log_updates | grep -Fq "Installing update version=${LABEL}"; then
    A_CLICKED=1
    break
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - A_START)) -ge "$AUTH_TIMEOUT" ]]; then
    break
  fi
  sleep "$POLL"
done
if [[ "$A_CLICKED" -ne 1 ]]; then
  echo "FAIL: Install and Relaunch button not found/clicked within ${AUTH_TIMEOUT}s" >&2
  exit 1
fi
echo "STEP 7: OK (clicked Install and Relaunch)"

# STEP 8: Wait for relaunch and version
echo "STEP 8: Wait for relaunch and version"
N_START="$(date +%s)"
NEW_PID=""
N_OK=0
while true; do
  CANDIDATES="$(e2e_app_pids || true)"
  CUR_VER="$(e2e_app_version_now || echo "unknown")"
  if [[ "$CUR_VER" == "$EXPECT_VERSION" ]]; then
    CAND_LINE=""
    while IFS= read -r CAND_LINE; do
      CAND_PID="$(printf '%s' "$CAND_LINE" | tr -d '[:space:]' || true)"
      if [[ -z "$CAND_PID" ]]; then
        continue
      fi
      if [[ "$CAND_PID" == "$OLD_PID" ]]; then
        continue
      fi
      if printf '%s\n' "$FEED_PIDS" | grep -Fxq "$CAND_PID"; then
        continue
      fi
      NEW_PID="$CAND_PID"
      N_OK=1
      break
    done <<< "$CANDIDATES"
    if [[ "$N_OK" -eq 1 ]]; then
      break
    fi
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - N_START)) -ge "$NEW_PID_WAIT" ]]; then
    break
  fi
  sleep "$POLL"
done
if [[ "$N_OK" -ne 1 ]]; then
  echo "FAIL: no new PID (old=$OLD_PID) with version $EXPECT_VERSION within ${NEW_PID_WAIT}s" >&2
  echo "last pids: $(e2e_app_pids | tr '\n' ' ' || true) version: $(e2e_app_version_now)" >&2
  exit 1
fi
echo "relaunched: old pid $OLD_PID -> new pid $NEW_PID version $EXPECT_VERSION"
echo "settling ${SETTLE_SECONDS}s..."
sleep "$SETTLE_SECONDS"
echo "STEP 8: OK"

# STEP 9: Checks
echo "STEP 9: Checks"
ALL_PASS=1
check_pass() {
  echo "CHECK $1: PASS ($2)"
}
check_fail() {
  echo "CHECK $1: FAIL ($2)"
  ALL_PASS=0
}

CUR_VERSION="$(e2e_app_version_now)"
if [[ "$CUR_VERSION" == "$EXPECT_VERSION" ]]; then
  check_pass "version" "$CUR_VERSION"
else
  check_fail "version" "got $CUR_VERSION expected $EXPECT_VERSION"
fi

APP_BUILD_NOW="$("$PLISTBUDDY" -c "Print :APM44BuildID" "$APP_INFO" 2>/dev/null || echo "unknown")"
DRIVER_BUILD_NOW="$("$PLISTBUDDY" -c "Print :APM44BuildID" "$DRIVER_INFO" 2>/dev/null || echo "unknown")"
HELPER_VER_OUT="$("$HELPER" --version 2>/dev/null || echo "")"
HELPER_BUILD_NOW="$(printf '%s\n' "$HELPER_VER_OUT" | sed -n 's/.*build=\([^ ]*\).*/\1/p' | head -n 1)"
if [[ -z "$HELPER_BUILD_NOW" ]]; then
  HELPER_BUILD_NOW="unknown"
fi
SHM_OUT="$("$HELPER" --shm-status 2>/dev/null || echo "")"
LOADED_BUILD_NOW="$(printf '%s\n' "$SHM_OUT" | sed -n 's/^driver_build_id=//p' | head -n 1 | tr -d '\r')"
if [[ -z "$LOADED_BUILD_NOW" ]]; then
  LOADED_BUILD_NOW="unknown"
fi
if [[ -n "$APP_BUILD_NOW" && "$APP_BUILD_NOW" != "unknown" && "$APP_BUILD_NOW" == "$DRIVER_BUILD_NOW" && "$APP_BUILD_NOW" == "$HELPER_BUILD_NOW" && "$APP_BUILD_NOW" == "$LOADED_BUILD_NOW" ]]; then
  check_pass "build-ids" "app=$APP_BUILD_NOW driver=$DRIVER_BUILD_NOW helper=$HELPER_BUILD_NOW loaded=$LOADED_BUILD_NOW"
else
  check_fail "build-ids" "app=$APP_BUILD_NOW driver=$DRIVER_BUILD_NOW helper=$HELPER_BUILD_NOW loaded=$LOADED_BUILD_NOW"
fi

PID_LIST="$(e2e_app_pids || true)"
if [[ -z "$PID_LIST" ]]; then
  PID_COUNT=0
else
  PID_COUNT="$(printf '%s\n' "$PID_LIST" | grep -c . || true)"
fi
if [[ "$PID_COUNT" -eq 1 ]]; then
  check_pass "single-app-process" "pid=$(printf '%s' "$PID_LIST" | tr -d '[:space:]')"
else
  check_fail "single-app-process" "count=$PID_COUNT pids=$(printf '%s' "$PID_LIST" | tr '\n' ' ')"
fi

WINDOWS_OUT="$("$OSASCRIPT" -e 'tell application "System Events" to tell process "APM44 Bridge" to get name of every window' 2>&1 || true)"
WINDOWS_TRIM="$(printf '%s' "$WINDOWS_OUT" | tr -d '[:space:]')"
if [[ -z "$WINDOWS_TRIM" || "$WINDOWS_TRIM" == "missingvalue" || "$WINDOWS_TRIM" == "{}" ]]; then
  check_pass "no-windows" "no windows"
else
  check_fail "no-windows" "windows: $WINDOWS_OUT"
fi

if e2e_log_updates 2>/dev/null | grep -Fq "Update failed"; then
  check_fail "no-update-failed" "found 'Update failed' in log"
else
  check_pass "no-update-failed" "no 'Update failed' lines"
fi

for DKEY in SUFeedURL APM44AutomationCheckForUpdates APM44AutomationStartBridge; do
  if "$DEFAULTS" read "$BUNDLE_ID" "$DKEY" >/dev/null 2>&1; then
    DVAL="$("$DEFAULTS" read "$BUNDLE_ID" "$DKEY" 2>/dev/null || echo "?")"
    check_fail "defaults-$DKEY" "persisted: $DVAL"
  else
    check_pass "defaults-$DKEY" "not persisted"
  fi
done

if [[ "$START_BRIDGE" -eq 1 ]]; then
  if e2e_log_bridge 2>/dev/null | grep -Fq "Bridge resuming after update"; then
    check_pass "bridge-resuming" "found 'Bridge resuming after update'"
  else
    check_fail "bridge-resuming" "missing 'Bridge resuming after update'"
  fi
  if "$PGREP" -f "apm44-bridge --virtual-device" >/dev/null 2>&1; then
    check_pass "bridge-helper" "helper process runs"
  else
    check_fail "bridge-helper" "helper process missing"
  fi
  if bash "$AUDIO_FLOW_SCRIPT" --seconds 3 --helper "$HELPER" >"$RUN_DIR/audio-flow.out" 2>&1; then
    check_pass "audio-flow" "e2e-check-audio-flow.sh passed"
  else
    AF_TAIL="$(tail -n 5 "$RUN_DIR/audio-flow.out" 2>/dev/null | tr '\n' ';' || echo "?")"
    check_fail "audio-flow" "audio flow failed: $AF_TAIL"
  fi
fi

if [[ -n "$START_BRIDGE_NOT_RUN_REASON" ]]; then
  for NR in bridge-resuming bridge-helper audio-flow; do
    echo "CHECK $NR: NOT RUN ($START_BRIDGE_NOT_RUN_REASON)"
  done
fi

# STEP 10: Summary
echo "STEP 10: Summary"
echo "===== E2E UPDATE SUMMARY ====="
echo "pkg: $PKG"
echo "expected: $EXPECT_VERSION label: $LABEL"
echo "old pid: $OLD_PID new pid: ${NEW_PID:-?}"
if [[ "$ALL_PASS" -eq 1 && -n "$START_BRIDGE_NOT_RUN_REASON" ]]; then
  echo "Result: PASS (all run checks passed; bridge checks NOT RUN: $START_BRIDGE_NOT_RUN_REASON)"
elif [[ "$ALL_PASS" -eq 1 ]]; then
  echo "Result: PASS (all checks passed)"
else
  echo "Result: FAIL (see CHECK lines above)"
fi
echo "run dir: $RUN_DIR"

if [[ "$ALL_PASS" -eq 1 ]]; then
  exit 0
else
  exit 1
fi
