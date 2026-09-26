#!/usr/bin/env bash
# Credential-free tests for end-to-end update tooling.
# No real app, no network, no audio, never touches /Applications.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FAKE_BIN="$TMP/bin"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

ROOT="$TMP/repo"
mkdir -p "$FAKE_BIN" "$ROOT/scripts"
cp "$SOURCE_ROOT/scripts/e2e-local-update-feed.sh" "$SOURCE_ROOT/scripts/e2e-check-audio-flow.sh" "$SOURCE_ROOT/scripts/e2e-update-roundtrip.sh" "$SOURCE_ROOT/scripts/ensure-sparkle-tools.sh" "$ROOT/scripts/"
chmod +x "$ROOT/scripts/"*.sh

reset_tmp() {
  rm -rf "$TMP/case"
  mkdir -p "$TMP/case"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "expected to find '$needle' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2 || true
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "did not expect to find '$needle' in $file" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2 || true
    exit 1
  fi
}

# ---- feed script fakes ----
write_fake_sign_update() {
  cat >"$FAKE_BIN/sign_update" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-p" ]]; then
  echo "FAKEEDSIGNATURE123"
  exit 0
fi
if [[ "${1:-}" == "--verify" ]]; then
  if [[ "${APM44_FAKE_VERIFY_FAIL:-0}" == "1" ]]; then
    echo "verify failed" >&2
    exit 1
  fi
  exit 0
fi
exit 0
EOF
  chmod +x "$FAKE_BIN/sign_update"
}

run_feed_success_case() {
  reset_tmp
  write_fake_sign_update
  local pkg="$TMP/case/candidate.pkg"
  local out="$TMP/case/feed-out"
  printf 'fake pkg content for length' >"$pkg"
  local expected_len
  expected_len="$(wc -c <"$pkg" | tr -d '[:space:]')"
  local logout="$TMP/case/feed.log"
  SPARKLE_SIGN_UPDATE="$FAKE_BIN/sign_update" \
    /bin/bash "$ROOT/scripts/e2e-local-update-feed.sh" --pkg "$pkg" --version "0.12.15" --out "$out" --port 8765 >"$logout" 2>&1
  assert_contains "$logout" "run dir:"
  [[ -f "$out/test.pkg" ]] || { echo "expected $out/test.pkg" >&2; exit 1; }
  [[ -f "$out/appcast.xml" ]] || { echo "expected $out/appcast.xml" >&2; exit 1; }
  assert_contains "$out/appcast.xml" "0.12.15"
  assert_contains "$out/appcast.xml" "http://127.0.0.1:8765/test.pkg"
  assert_contains "$out/appcast.xml" "FAKEEDSIGNATURE123"
  assert_contains "$out/appcast.xml" "length=\"$expected_len\""
  assert_contains "$out/appcast.xml" 'sparkle:installationType="package"'
  assert_contains "$out/appcast.xml" 'type="application/octet-stream"'
  assert_contains "$out/appcast.xml" "sparkle:version"
  assert_contains "$out/appcast.xml" "sparkle:shortVersionString"
}

run_feed_verify_fail_case() {
  reset_tmp
  write_fake_sign_update
  local pkg="$TMP/case/candidate.pkg"
  local out="$TMP/case/feed-out"
  printf 'fake pkg' >"$pkg"
  local logout="$TMP/case/feed-fail.log"
  local status=0
  if SPARKLE_SIGN_UPDATE="$FAKE_BIN/sign_update" APM44_FAKE_VERIFY_FAIL=1 \
    /bin/bash "$ROOT/scripts/e2e-local-update-feed.sh" --pkg "$pkg" --version "0.12.15" --out "$out" --port 8765 >"$logout" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "feed should fail when --verify fails" >&2
    cat "$logout" >&2
    exit 1
  fi
}

run_feed_help_case() {
  local out="$TMP/case-feed-help.out"
  /bin/bash "$ROOT/scripts/e2e-local-update-feed.sh" --help >"$out" 2>&1
  assert_contains "$out" "Usage:"
}

# ---- audio flow decision ----
run_audio_decision_cases() {
  local lib_out="$TMP/case-audio-lib.out"
  reset_tmp
  # Source logic only; must not run main or touch audio.
  E2E_AUDIO_FLOW_LIB_ONLY=1
  # shellcheck disable=SC1090
  . "$ROOT/scripts/e2e-check-audio-flow.sh"
  unset E2E_AUDIO_FLOW_LIB_ONLY

  local before_good='shm_status=ok
daemon_ready=1
write_index=100000
read_index=100000
producer_dropped_frames=0
driver_build_id=ABC'
  local after_good='shm_status=ok
daemon_ready=1
write_index=200000
read_index=200000
producer_dropped_frames=0
driver_build_id=ABC'
  local after_stalled='shm_status=ok
daemon_ready=1
write_index=200000
read_index=100010
producer_dropped_frames=0
driver_build_id=ABC'
  local after_dropped='shm_status=ok
daemon_ready=1
write_index=200000
read_index=200000
producer_dropped_frames=5
driver_build_id=ABC'
  local after_notready='shm_status=ok
daemon_ready=0
write_index=200000
read_index=200000
producer_dropped_frames=0
driver_build_id=ABC'
  local after_badshm='shm_status=failed
daemon_ready=1
write_index=200000
read_index=200000
producer_dropped_frames=0
driver_build_id=ABC'

  local out="$TMP/case/audio.out"
  local status=0

  if ! e2e_audio_flow_check_texts "$before_good" "$after_good" 3 >"$out" 2>&1; then
    echo "advancing indices should PASS" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "PASS"

  status=0
  if e2e_audio_flow_check_texts "$before_good" "$after_stalled" 3 >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "stalled read_index should FAIL" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "FAIL"

  status=0
  if e2e_audio_flow_check_texts "$before_good" "$after_dropped" 3 >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "dropped frames increase should FAIL" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "FAIL"

  status=0
  if e2e_audio_flow_check_texts "$before_good" "$after_notready" 3 >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "daemon_ready=0 should FAIL" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "FAIL"

  status=0
  if e2e_audio_flow_check_texts "$before_good" "$after_badshm" 3 >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "shm_status failed should FAIL" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "FAIL"

  # Audio script help works without audio.
  /bin/bash "$ROOT/scripts/e2e-check-audio-flow.sh" --help >"$lib_out" 2>&1
  assert_contains "$lib_out" "Usage:"
}

# ---- roundtrip fakes ----
write_roundtrip_fakes() {
  local state="$1"
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/sign_update" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-p" ]]; then
  echo "FAKEEDSIGNATURE123"
  exit 0
fi
if [[ "${1:-}" == "--verify" ]]; then
  exit 0
fi
exit 0
EOF
  cat >"$FAKE_BIN/pgrep" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
args="\$*"
if echo "\$args" | grep -q "SUFeedURL"; then
  [[ -f "\$STATE_DIR/app_has_test_args" ]] && { echo 999; exit 0; }
  exit 1
fi
if echo "\$args" | grep -q "apm44-bridge --virtual-device"; then
  if [[ -f "\$STATE_DIR/bridge_running" ]]; then
    cat "\$STATE_DIR/helper_pid"
    exit 0
  fi
  exit 1
fi
if echo "\$args" | grep -q "APM44 Bridge"; then
  if [[ -f "\$STATE_DIR/app_pid" ]]; then
    pid="\$(cat "\$STATE_DIR/app_pid" 2>/dev/null || true)"
    if [[ -n "\$pid" ]]; then
      printf '%s\n' "\$pid"
      exit 0
    fi
  fi
  exit 1
fi
exit 1
EOF
  cat >"$FAKE_BIN/pkill" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat >"$FAKE_BIN/PlistBuddy" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
key=""
if [[ "\${1:-}" == "-c" ]]; then
  key="\$(printf '%s' "\${2:-}" | sed 's/.*Print ://')"
fi
plist="\${@: -1}"
if [[ "\$key" == "CFBundleShortVersionString" ]]; then
  cat "\$STATE_DIR/app_version"
  exit 0
fi
if [[ "\$key" == "APM44BuildID" ]]; then
  if printf '%s' "\$plist" | grep -q "APM44Bridge.driver"; then
    cat "\$STATE_DIR/driver_build"
    exit 0
  else
    cat "\$STATE_DIR/app_build"
    exit 0
  fi
fi
echo "unsupported fake PlistBuddy: \$*" >&2
exit 64
EOF
  cat >"$FAKE_BIN/apm44-bridge" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
if [[ "\${1:-}" == "--version" ]]; then
  ver="\$(cat "\$STATE_DIR/app_version")"
  build="\$(cat "\$STATE_DIR/helper_build")"
  echo "apm44-bridge \$ver build=\$build extra"
  exit 0
fi
if [[ "\${1:-}" == "--list-devices" ]]; then
  printf 'UID\tNAME\tRATE\tI/O\tALIVE\n'
  if [[ ! -f "\$STATE_DIR/output_missing" ]]; then
    printf 'test-output-uid\tTest Output\t48000\tO\t1\n'
  fi
  exit 0
fi
if [[ "\${1:-}" == "--shm-status" ]]; then
  echo "shm_status=ok"
  echo "daemon_ready=1"
  echo "write_index=1000000"
  echo "read_index=1000000"
  echo "producer_dropped_frames=0"
  printf 'driver_build_id=%s\n' "\$(cat "\$STATE_DIR/loaded_build")"
  exit 0
fi
exit 0
EOF
  cat >"$FAKE_BIN/log" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
args="\$*"
if printf '%s' "\$args" | grep -q 'category == "Bridge"'; then
  if [[ -f "\$STATE_DIR/updated" ]]; then
    echo "Bridge resuming after update"
    echo "Bridge running"
  fi
  exit 0
fi
if [[ "\${APM44_E2E_FAKE_UPDATE_FAILED:-0}" == "1" ]]; then
  echo "Update failed simulated"
fi
label="\$(cat "\$STATE_DIR/expected_label" 2>/dev/null || echo "0.12.15")"
if [[ -f "\$STATE_DIR/no_update_available" ]]; then
  exit 0
fi
echo "Update available version=\$label"
if [[ -f "\$STATE_DIR/downloaded" ]]; then
  echo "Update downloaded version=\$label"
fi
if [[ -f "\$STATE_DIR/updated" ]]; then
  echo "Installing update version=\$label"
fi
exit 0
EOF
  cat >"$FAKE_BIN/osascript" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
args="\$*"
if printf '%s' "\$args" | grep -q "first process"; then
  echo "Finder"
  exit 0
fi
if printf '%s' "\$args" | grep -q 'tell application "APM44 Bridge" to quit'; then
  : > "\$STATE_DIR/app_pid"
  exit 0
fi
if printf '%s' "\$args" | grep -q "name of every window"; then
  if [[ -f "\$STATE_DIR/windows" ]]; then
    cat "\$STATE_DIR/windows"
  fi
  exit 0
fi
if printf '%s' "\$args" | grep -q '"Install Update"'; then
  # The click starts the download; with install_click_errors the call itself
  # reports an error (Sparkle closed the window mid-click), as seen for real.
  touch "\$STATE_DIR/downloaded"
  if [[ -f "\$STATE_DIR/install_click_errors" ]]; then
    exit 1
  fi
  exit 0
fi
if printf '%s' "\$args" | grep -q "Install and Relaunch"; then
  cat "\$STATE_DIR/new_pid" > "\$STATE_DIR/app_pid"
  cat "\$STATE_DIR/new_version" > "\$STATE_DIR/app_version"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/app_build"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/driver_build"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/helper_build"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/loaded_build"
  touch "\$STATE_DIR/updated"; rm -f "\$STATE_DIR/app_has_test_args"
  exit 0
fi
if printf '%s' "\$args" | grep -q "neu starten"; then
  cat "\$STATE_DIR/new_pid" > "\$STATE_DIR/app_pid"
  cat "\$STATE_DIR/new_version" > "\$STATE_DIR/app_version"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/app_build"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/driver_build"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/helper_build"
  cat "\$STATE_DIR/new_build" > "\$STATE_DIR/loaded_build"
  touch "\$STATE_DIR/updated"; rm -f "\$STATE_DIR/app_has_test_args"
  exit 0
fi
exit 0
EOF
  cat >"$FAKE_BIN/open" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
if [[ ! -s "\$STATE_DIR/app_pid" ]]; then
  cat "\$STATE_DIR/old_pid" > "\$STATE_DIR/app_pid"
fi
if printf '%s' "\$*" | grep -q "SUFeedURL"; then
  touch "\$STATE_DIR/app_has_test_args"
else
  rm -f "\$STATE_DIR/app_has_test_args"
  touch "\$STATE_DIR/plain_relaunch"
fi
exit 0
EOF
  cat >"$FAKE_BIN/curl" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
if [[ -f "\$STATE_DIR/server_running" ]]; then
  exit 0
fi
exit 7
EOF
  cat >"$FAKE_BIN/python3" <<EOF
#!/bin/bash
set -euo pipefail
STATE_DIR="$state"
if printf '%s' "\$*" | grep -q "http.server"; then
  touch "\$STATE_DIR/server_running"
  # Behave like a real long-running server so cleanup must actually kill it.
  echo "\$\$" >"\$STATE_DIR/server_pid"
  exec sleep 300
fi
exit 0
EOF
  cat >"$FAKE_BIN/defaults" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${3:-}" == "apm44.outputDeviceUid" ]]; then
  echo "test-output-uid"
  exit 0
fi
if [[ "${APM44_E2E_FAKE_DEFAULTS_PERSISTED:-0}" == "1" ]]; then
  echo "persisted-value"
  exit 0
fi
exit 1
EOF
  cat >"$FAKE_BIN/say" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-a" && "${2:-}" == "?" ]]; then
  echo "112 APM44 Bridge"
  exit 0
fi
exit 0
EOF
  cat >"$FAKE_BIN/fake-audio-flow.sh" <<'EOF'
#!/bin/bash
echo "CHECK audio: PASS (fake)"
exit 0
EOF
  chmod +x "$FAKE_BIN/"*
}

setup_roundtrip_state() {
  local state="$1"
  local windows_content="$2"
  rm -rf "$state"
  mkdir -p "$state"
  printf '111\n' >"$state/app_pid"
  printf '111\n' >"$state/old_pid"
  printf '222\n' >"$state/new_pid"
  printf '0.12.14\n' >"$state/app_version"
  printf '0.12.15\n' >"$state/new_version"
  printf '0.12.15\n' >"$state/expected_label"
  printf 'OLD123\n' >"$state/app_build"
  printf 'OLD123\n' >"$state/driver_build"
  printf 'OLD123\n' >"$state/helper_build"
  printf 'OLD123\n' >"$state/loaded_build"
  printf 'NEW456\n' >"$state/new_build"
  printf '333\n' >"$state/helper_pid"
  touch "$state/bridge_running"
  printf '%s' "$windows_content" >"$state/windows"
  rm -f "$state/updated" "$state/server_running"
  # After the fake install, build ids become NEW456; pre-seed new_build as NEW456
  # and make the final state consistent by pointing new files at NEW456.
  printf 'NEW456\n' >"$state/new_build"
}

run_roundtrip_help_case() {
  local out="$TMP/case-rt-help.out"
  /bin/bash "$ROOT/scripts/e2e-update-roundtrip.sh" --help >"$out" 2>&1
  assert_contains "$out" "Usage:"
}

run_roundtrip_missing_pkg_case() {
  local out="$TMP/case-rt-missing.out"
  local status=0
  if /bin/bash "$ROOT/scripts/e2e-update-roundtrip.sh" --expect-version 0.12.15 --yes >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "missing --pkg should fail" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "--pkg"
}

run_roundtrip_happy_case() {
  # $1 installed version before the update, $2 feed label (run 2 re-offers the
  # candidate under a higher label to an app that already has the hooks).
  local installed="${1:-0.12.14}"
  local label="${2:-0.12.15}"
  local click_errors="${3:-no}"
  local state="$TMP/case-rt-state-$installed-$label-$click_errors"
  setup_roundtrip_state "$state" ""
  printf '%s\n' "$installed" >"$state/app_version"
  printf '%s\n' "$label" >"$state/expected_label"
  if [[ "$click_errors" == "click-errors" ]]; then
    touch "$state/install_click_errors"
  fi
  # Empty windows file means no windows.
  : >"$state/windows"
  # After update the fake osascript copies new_build (NEW456) everywhere, but
  # app_version/new_version must converge to the expected label. Align the
  # final build files so the build-id check passes.
  printf 'NEW456\n' >"$state/new_build"
  write_roundtrip_fakes "$state"
  local fake_app="$TMP/case-rt-app/APM44 Bridge.app"
  local fake_driver="$TMP/case-rt-driver/APM44Bridge.driver"
  mkdir -p "$fake_app/Contents" "$fake_driver/Contents"
  printf 'fake app\n' >"$fake_app/Contents/Info.plist"
  printf 'fake driver\n' >"$fake_driver/Contents/Info.plist"
  local pkg="$TMP/case-rt-pkg.pkg"
  printf 'candidate pkg bytes' >"$pkg"
  local out="$TMP/case-rt-happy-$installed-$label-$click_errors.out"
  local status=0
  if env \
    PATH="$FAKE_BIN:$PATH" \
    SPARKLE_SIGN_UPDATE="$FAKE_BIN/sign_update" \
    APM44_E2E_APP_PATH="$fake_app" \
    APM44_E2E_DRIVER_PATH="$fake_driver" \
    APM44_E2E_HELPER="$FAKE_BIN/apm44-bridge" \
    APM44_E2E_OSASCRIPT="$FAKE_BIN/osascript" \
    APM44_E2E_OPEN="$FAKE_BIN/open" \
    APM44_E2E_PGREP="$FAKE_BIN/pgrep" \
    APM44_E2E_PKILL="$FAKE_BIN/pkill" \
    APM44_E2E_LOG="$FAKE_BIN/log" \
    APM44_E2E_DEFAULTS="$FAKE_BIN/defaults" \
    APM44_E2E_CURL="$FAKE_BIN/curl" \
    APM44_E2E_PYTHON3="$FAKE_BIN/python3" \
    APM44_E2E_PLISTBUDDY="$FAKE_BIN/PlistBuddy" \
    APM44_E2E_FEED_SCRIPT="$ROOT/scripts/e2e-local-update-feed.sh" \
    APM44_E2E_AUDIO_FLOW_SCRIPT="$FAKE_BIN/fake-audio-flow.sh" \
    APM44_E2E_FAKE_STATE="$state" \
    APM44_E2E_SETTLE_SECONDS=0 \
    APM44_E2E_POLL_INTERVAL=1 \
    /bin/bash "$ROOT/scripts/e2e-update-roundtrip.sh" --pkg "$pkg" --expect-version "0.12.15" --label "$label" --start-bridge --yes >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "happy path should exit 0, got $status" >&2
    cat "$out" >&2
    exit 1
  fi
  # Step order.
  local s1 s2 s3 s4 s5 s6 s7 s8 s9 s10
  s1="$(grep -n "STEP 1:" "$out" | head -1 | cut -d: -f1 || true)"
  s2="$(grep -n "STEP 2:" "$out" | head -1 | cut -d: -f1 || true)"
  s3="$(grep -n "STEP 3:" "$out" | head -1 | cut -d: -f1 || true)"
  s4="$(grep -n "STEP 4:" "$out" | head -1 | cut -d: -f1 || true)"
  s5="$(grep -n "STEP 5:" "$out" | head -1 | cut -d: -f1 || true)"
  s6="$(grep -n "STEP 6:" "$out" | head -1 | cut -d: -f1 || true)"
  s7="$(grep -n "STEP 7:" "$out" | head -1 | cut -d: -f1 || true)"
  s8="$(grep -n "STEP 8:" "$out" | head -1 | cut -d: -f1 || true)"
  s9="$(grep -n "STEP 9:" "$out" | head -1 | cut -d: -f1 || true)"
  s10="$(grep -n "STEP 10:" "$out" | head -1 | cut -d: -f1 || true)"
  if [[ -z "$s1" || -z "$s2" || -z "$s3" || -z "$s4" || -z "$s5" || -z "$s6" || -z "$s7" || -z "$s8" || -z "$s9" || -z "$s10" ]]; then
    echo "missing STEP lines in order" >&2
    cat "$out" >&2
    exit 1
  fi
  if [[ "$s1" -ge "$s2" || "$s2" -ge "$s3" || "$s3" -ge "$s4" || "$s4" -ge "$s5" || "$s5" -ge "$s6" || "$s6" -ge "$s7" || "$s7" -ge "$s8" || "$s8" -ge "$s9" || "$s9" -ge "$s10" ]]; then
    echo "STEP order is wrong" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "ACTION REQUIRED: approve the macOS admin prompt (Touch ID or password) for APM44 Bridge"
  assert_contains "$out" "CHECK version: PASS"
  assert_contains "$out" "CHECK build-ids: PASS"
  assert_contains "$out" "CHECK single-app-process: PASS"
  assert_contains "$out" "CHECK no-windows: PASS"
  assert_contains "$out" "CHECK no-update-failed: PASS"
  assert_contains "$out" "Result: PASS"
  assert_contains "$out" "run dir:"
  if [[ "$installed" == "0.12.14" ]]; then
    # The installed app predates the automation hooks: bridge checks are NOT RUN, not FAIL.
    assert_contains "$out" "STEP 4: NOT RUN (installed 0.12.14 predates the automation hooks"
    assert_contains "$out" "CHECK bridge-resuming: NOT RUN"
    assert_contains "$out" "CHECK audio-flow: NOT RUN"
    assert_contains "$out" "bridge checks NOT RUN"
  else
    assert_contains "$out" "STEP 4: OK (bridge was running)"
    assert_contains "$out" "CHECK bridge-resuming: PASS"
    assert_contains "$out" "CHECK bridge-helper: PASS"
    assert_contains "$out" "CHECK audio-flow: PASS"
  fi
  # Must never touch the real install.
  assert_not_contains "$out" "/Applications/APM44 Bridge.app"
  # After a successful update Sparkle relaunches the app without test args.
  assert_not_contains "$out" "cleanup: relaunched APM44 Bridge"
  assert_server_stopped "$state"
}

run_roundtrip_output_missing_case() {
  local state="$TMP/case-rt-state-nooutput"
  setup_roundtrip_state "$state" ""
  printf '0.12.15\n' >"$state/app_version"
  touch "$state/output_missing"
  write_roundtrip_fakes "$state"
  local fake_app="$TMP/case-rt-app-nooutput/APM44 Bridge.app"
  mkdir -p "$fake_app/Contents"
  printf 'fake app\n' >"$fake_app/Contents/Info.plist"
  local pkg="$TMP/case-rt-pkg-nooutput.pkg"
  printf 'candidate pkg bytes' >"$pkg"
  local out="$TMP/case-rt-nooutput.out"
  if env \
    PATH="$FAKE_BIN:$PATH" \
    SPARKLE_SIGN_UPDATE="$FAKE_BIN/sign_update" \
    APM44_E2E_APP_PATH="$fake_app" \
    APM44_E2E_HELPER="$FAKE_BIN/apm44-bridge" \
    APM44_E2E_OSASCRIPT="$FAKE_BIN/osascript" \
    APM44_E2E_PGREP="$FAKE_BIN/pgrep" \
    APM44_E2E_DEFAULTS="$FAKE_BIN/defaults" \
    APM44_E2E_CURL="$FAKE_BIN/curl" \
    APM44_E2E_PYTHON3="$FAKE_BIN/python3" \
    APM44_E2E_PLISTBUDDY="$FAKE_BIN/PlistBuddy" \
    APM44_E2E_FAKE_STATE="$state" \
    /bin/bash "$ROOT/scripts/e2e-update-roundtrip.sh" --pkg "$pkg" --expect-version "0.12.15" --label 99.0.0 --start-bridge --yes >"$out" 2>&1; then
    echo "missing output should fail in preflight" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "FAIL: the selected output (test-output-uid) is not connected"
  assert_not_contains "$out" "STEP 2:"
  [[ ! -f "$state/server_running" ]] || { echo "server must not start when preflight fails" >&2; exit 1; }
}

run_roundtrip_restores_app_on_fail_case() {
  local state="$TMP/case-rt-state-restore"
  setup_roundtrip_state "$state" ""
  touch "$state/no_update_available"
  write_roundtrip_fakes "$state"
  local fake_app="$TMP/case-rt-app-restore/APM44 Bridge.app"
  mkdir -p "$fake_app/Contents"
  printf 'fake app\n' >"$fake_app/Contents/Info.plist"
  local pkg="$TMP/case-rt-pkg-restore.pkg"
  printf 'candidate pkg bytes' >"$pkg"
  local out="$TMP/case-rt-restore.out"
  if env \
    PATH="$FAKE_BIN:$PATH" \
    SPARKLE_SIGN_UPDATE="$FAKE_BIN/sign_update" \
    APM44_E2E_APP_PATH="$fake_app" \
    APM44_E2E_HELPER="$FAKE_BIN/apm44-bridge" \
    APM44_E2E_OSASCRIPT="$FAKE_BIN/osascript" \
    APM44_E2E_OPEN="$FAKE_BIN/open" \
    APM44_E2E_PGREP="$FAKE_BIN/pgrep" \
    APM44_E2E_PKILL="$FAKE_BIN/pkill" \
    APM44_E2E_LOG="$FAKE_BIN/log" \
    APM44_E2E_DEFAULTS="$FAKE_BIN/defaults" \
    APM44_E2E_CURL="$FAKE_BIN/curl" \
    APM44_E2E_PYTHON3="$FAKE_BIN/python3" \
    APM44_E2E_PLISTBUDDY="$FAKE_BIN/PlistBuddy" \
    APM44_E2E_FEED_SCRIPT="$ROOT/scripts/e2e-local-update-feed.sh" \
    APM44_E2E_FAKE_STATE="$state" \
    APM44_E2E_UPDATE_WAIT=2 \
    APM44_E2E_QUIT_WAIT=1 \
    APM44_E2E_POLL_INTERVAL=1 \
    /bin/bash "$ROOT/scripts/e2e-update-roundtrip.sh" --pkg "$pkg" --expect-version "0.12.15" --yes >"$out" 2>&1; then
    echo "a run without 'Update available' must fail" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "FAIL: did not see 'Update available version=0.12.15'"
  assert_contains "$out" "cleanup: relaunched APM44 Bridge without test arguments"
  [[ -f "$state/plain_relaunch" && ! -f "$state/app_has_test_args" ]] || { echo "app must end relaunched without test arguments" >&2; exit 1; }
  assert_server_stopped "$state"
}

run_roundtrip_windows_fail_case() {
  local state="$TMP/case-rt-state-fail"
  setup_roundtrip_state "$state" "Fehler beim Aktualisieren"
  write_roundtrip_fakes "$state"
  local fake_app="$TMP/case-rt-app-fail/APM44 Bridge.app"
  local fake_driver="$TMP/case-rt-driver-fail/APM44Bridge.driver"
  mkdir -p "$fake_app/Contents" "$fake_driver/Contents"
  printf 'fake app\n' >"$fake_app/Contents/Info.plist"
  printf 'fake driver\n' >"$fake_driver/Contents/Info.plist"
  local pkg="$TMP/case-rt-pkg-fail.pkg"
  printf 'candidate pkg bytes' >"$pkg"
  local out="$TMP/case-rt-fail.out"
  local status=0
  if env \
    PATH="$FAKE_BIN:$PATH" \
    SPARKLE_SIGN_UPDATE="$FAKE_BIN/sign_update" \
    APM44_E2E_APP_PATH="$fake_app" \
    APM44_E2E_DRIVER_PATH="$fake_driver" \
    APM44_E2E_HELPER="$FAKE_BIN/apm44-bridge" \
    APM44_E2E_OSASCRIPT="$FAKE_BIN/osascript" \
    APM44_E2E_OPEN="$FAKE_BIN/open" \
    APM44_E2E_PGREP="$FAKE_BIN/pgrep" \
    APM44_E2E_PKILL="$FAKE_BIN/pkill" \
    APM44_E2E_LOG="$FAKE_BIN/log" \
    APM44_E2E_DEFAULTS="$FAKE_BIN/defaults" \
    APM44_E2E_CURL="$FAKE_BIN/curl" \
    APM44_E2E_PYTHON3="$FAKE_BIN/python3" \
    APM44_E2E_PLISTBUDDY="$FAKE_BIN/PlistBuddy" \
    APM44_E2E_FEED_SCRIPT="$ROOT/scripts/e2e-local-update-feed.sh" \
    APM44_E2E_AUDIO_FLOW_SCRIPT="$FAKE_BIN/fake-audio-flow.sh" \
    APM44_E2E_FAKE_STATE="$state" \
    APM44_E2E_SETTLE_SECONDS=0 \
    APM44_E2E_POLL_INTERVAL=1 \
    /bin/bash "$ROOT/scripts/e2e-update-roundtrip.sh" --pkg "$pkg" --expect-version "0.12.15" --yes >"$out" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "error-alert window should make roundtrip FAIL" >&2
    cat "$out" >&2
    exit 1
  fi
  assert_contains "$out" "CHECK no-windows: FAIL"
  assert_contains "$out" "Result: FAIL"
  assert_server_stopped "$state"
}

# Regression: the feed server must not survive the script, even on FAIL
# (a subshell wrapper once orphaned it and blocked the next run's port).
assert_server_stopped() {
  local spid
  spid="$(cat "$1/server_pid" 2>/dev/null || true)"
  if [[ -z "$spid" ]]; then
    echo "fake server never started (no server_pid in $1)" >&2
    exit 1
  fi
  local i
  for i in 1 2 3 4 5; do
    kill -0 "$spid" 2>/dev/null || return 0
    sleep 0.2
  done
  kill "$spid" 2>/dev/null || true
  echo "feed server pid $spid still running after the script exited" >&2
  exit 1
}

run_feed_success_case
run_feed_verify_fail_case
run_feed_help_case
run_audio_decision_cases
run_roundtrip_help_case
run_roundtrip_missing_pkg_case
run_roundtrip_happy_case 0.12.14 0.12.15
run_roundtrip_happy_case 0.12.15 99.0.0
run_roundtrip_happy_case 0.12.15 99.0.0 click-errors
run_roundtrip_output_missing_case
run_roundtrip_restores_app_on_fail_case
run_roundtrip_windows_fail_case

echo "e2e script tests: OK"
