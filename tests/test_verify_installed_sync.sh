#!/usr/bin/env bash
# Fixture-driven regression for scripts/verify-installed-sync.sh.
# Uses fake bridge/helper binaries; no real hardware, CoreAudio, or installs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-installed-sync.sh"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

EXPECTED="0.12.7+3fc0fake001"
MISMATCH="0.12.7+c272fake002"
MISSING_DRIVER="$TMP/no-such-driver"

PASS=0
FAIL=0

make_app_with_helper() {
  local app="$1"
  mkdir -p "$app/Contents/MacOS"
  cat >"$app/Contents/MacOS/apm44-bridge" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "apm44-bridge 0.12.7 build=$EXPECTED"
  exit 0
fi
echo "helper fake: unsupported arg" >&2
exit 64
EOF
  chmod +x "$app/Contents/MacOS/apm44-bridge"
}

make_driver_bundle() {
  local driver="$1"
  local build_id="$2"
  mkdir -p "$driver/Contents"
  cat >"$driver/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>org.apm44.bridge.driver</string>
  <key>APM44BuildID</key>
  <string>$build_id</string>
</dict>
</plist>
EOF
}

# make_bridge <path> <mode>: mode selects --shm-status behavior.
# --version always reports EXPECTED so repo/helper match passes.
make_bridge() {
  local path="$1"
  local mode="$2"
  case "$mode" in
    success)
      cat >"$path" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "apm44-bridge 0.12.7 build=$EXPECTED"
  exit 0
fi
if [[ "\${1:-}" == "--shm-status" ]]; then
  echo "shm_status=ok"
  echo "helper_build_id=$EXPECTED"
  echo "driver_build_id=$EXPECTED"
  exit 0
fi
echo "bridge fake: unsupported arg" >&2
exit 64
EOF
      ;;
    invalid_header)
      cat >"$path" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "apm44-bridge 0.12.7 build=$EXPECTED"
  exit 0
fi
if [[ "\${1:-}" == "--shm-status" ]]; then
  echo "shm_status=failed" >&2
  echo "helper_build_id=$EXPECTED" >&2
  echo "error_code=invalid_header" >&2
  exit 3
fi
echo "bridge fake: unsupported arg" >&2
exit 64
EOF
      ;;
    missing_ring)
      cat >"$path" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "apm44-bridge 0.12.7 build=$EXPECTED"
  exit 0
fi
if [[ "\${1:-}" == "--shm-status" ]]; then
  echo "shm_status=failed" >&2
  echo "helper_build_id=$EXPECTED" >&2
  echo "error_code=open_failed" >&2
  exit 2
fi
echo "bridge fake: unsupported arg" >&2
exit 64
EOF
      ;;
    missing_driver_id)
      cat >"$path" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "apm44-bridge 0.12.7 build=$EXPECTED"
  exit 0
fi
if [[ "\${1:-}" == "--shm-status" ]]; then
  echo "shm_status=ok"
  echo "helper_build_id=$EXPECTED"
  exit 0
fi
echo "bridge fake: unsupported arg" >&2
exit 64
EOF
      ;;
    driver_mismatch)
      cat >"$path" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "apm44-bridge 0.12.7 build=$EXPECTED"
  exit 0
fi
if [[ "\${1:-}" == "--shm-status" ]]; then
  echo "shm_status=ok"
  echo "helper_build_id=$EXPECTED"
  echo "driver_build_id=$MISMATCH"
  exit 0
fi
echo "bridge fake: unsupported arg" >&2
exit 64
EOF
      ;;
    *)
      echo "unknown bridge mode: $mode" >&2
      exit 64
      ;;
  esac
  chmod +x "$path"
}

run_case() {
  local desc="$1"
  local mode="$2"
  local expected_exit="$3"
  shift 3
  local case_dir="$TMP/$mode"
  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  local app="$case_dir/APM44 Bridge.app"
  local bridge="$case_dir/apm44-bridge"
  local driver="$case_dir/APM44Bridge.driver"
  make_app_with_helper "$app"
  make_bridge "$bridge" "$mode"
  make_driver_bundle "$driver" "$EXPECTED"
  local status=0
  set +e
  APM44_APP_PATH="$app" APM44_BRIDGE_BIN="$bridge" APM44_DRIVER_PATH="$driver" \
    bash "$VERIFY" "$@" >"$TMP/out.txt" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: expected exit $expected_exit, got $status" >&2
    cat "$TMP/out.txt" >&2
  fi
}

run_case_without_driver() {
  local desc="$1"
  local mode="$2"
  local expected_exit="$3"
  shift 3
  local case_dir="$TMP/$mode-no-driver"
  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  local app="$case_dir/APM44 Bridge.app"
  local bridge="$case_dir/apm44-bridge"
  make_app_with_helper "$app"
  make_bridge "$bridge" "$mode"
  local status=0
  set +e
  APM44_APP_PATH="$app" APM44_BRIDGE_BIN="$bridge" APM44_DRIVER_PATH="$MISSING_DRIVER" \
    bash "$VERIFY" "$@" >"$TMP/out.txt" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: expected exit $expected_exit, got $status" >&2
    cat "$TMP/out.txt" >&2
  fi
}

expect_output_contains() {
  local desc="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$TMP/out.txt"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: expected output to contain '$needle'" >&2
    cat "$TMP/out.txt" >&2
  fi
}

# 1. Success: bundle+ring with matching helper, driver, and shm IDs.
run_case "success exits 0" success 0
expect_output_contains "success reports live sync" "shm_driver_build_id=$EXPECTED"
expect_output_contains "success reports OK" "verify-installed-sync: OK"
expect_output_contains "success reports driver match" "OK: installed driver build ID matches helper"

# 2. invalid_header on stderr with exit 3 must fail, not warn-and-pass.
run_case "invalid_header exits nonzero" invalid_header 1
expect_output_contains "invalid_header diagnostic names error" "invalid_header"
expect_output_contains "invalid_header reports FAIL" "FAIL:"

# 3. Missing ring (open_failed, exit 2) is failed live proof with explicit reason.
run_case "missing ring exits nonzero" missing_ring 1
expect_output_contains "missing ring diagnostic names open_failed" "open_failed"
expect_output_contains "missing ring reports FAIL" "FAIL:"

# 4. shm_status=ok without driver_build_id must fail.
run_case "missing driver ID exits nonzero" missing_driver_id 1
expect_output_contains "missing driver ID diagnostic" "driver_build_id"
expect_output_contains "missing driver ID reports FAIL" "FAIL:"

# 5. Driver build ID unequal to helper must fail.
run_case "driver mismatch exits nonzero" driver_mismatch 1
expect_output_contains "driver mismatch diagnostic names live driver" "$MISMATCH"
expect_output_contains "driver mismatch reports FAIL" "FAIL:"

# 6. Missing driver bundle with shm_status=ok must fail, not warn-and-pass.
run_case_without_driver "missing driver bundle exits nonzero" success 1
expect_output_contains "missing driver bundle diagnostic" "installed HAL driver missing"
expect_output_contains "missing driver bundle reports FAIL" "FAIL:"

# 7. Dry run skips live shm even when the live ring would fail, without a driver.
run_case_without_driver "dry run skips live shm" invalid_header 0 --dry-run
expect_output_contains "dry run skips live shm" "dry-run: skipping live --shm-status"

echo "verify-installed-sync tests: $PASS passed, $FAIL failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
echo "verify-installed-sync tests: OK"
