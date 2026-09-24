#!/usr/bin/env bash
# Focused regression for scripts/verify-devices.sh using a mocked system_profiler.
# No real audio hardware required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-devices.sh"
TMP="$(mktemp -d)"
FAKE_BIN="$TMP/bin"
PROFILE_FILE="$TMP/profile.txt"
DEVICE_ROWS_FILE="$TMP/devices.txt"
mkdir -p "$FAKE_BIN"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

cat >"$FAKE_BIN/system_profiler" <<EOF
#!/bin/bash
cat "$PROFILE_FILE" 2>/dev/null || true
EOF
chmod +x "$FAKE_BIN/system_profiler"

cat >"$FAKE_BIN/apm44-bridge" <<EOF
#!/bin/bash
cat "$DEVICE_ROWS_FILE" 2>/dev/null || true
EOF
chmod +x "$FAKE_BIN/apm44-bridge"
export APM44_BRIDGE_BIN="$FAKE_BIN/apm44-bridge"

export PATH="$FAKE_BIN:/usr/bin:/bin"

PASS=0
FAIL=0

set_profile() {
  if [[ $# -eq 0 ]]; then
    : >"$PROFILE_FILE"
  else
    printf '%s\n' "$1" >"$PROFILE_FILE"
  fi
  set_airpods_device 48000 1970496032
}

set_airpods_device() {
  printf 'UID\tNAME\tRATE\tI/O\tALIVE\tOUTPUT_CHANNELS\tBUFFER_FRAMES\tTRANSPORT\n' >"$DEVICE_ROWS_FILE"
  printf 'airpods-output\tAirPods Max USB Audio\t%s\tO\t1\t2\t512\t%s\n' "$1" "$2" >>"$DEVICE_ROWS_FILE"
}

expect_exit() {
  local desc="$1"
  local expected="$2"
  shift 2
  local status=0
  set +e
  PATH="$FAKE_BIN:/usr/bin:/bin" bash "$VERIFY" "$@" >"$TMP/out.txt" 2>&1
  status=$?
  set -e
  if [[ "$status" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: expected exit $expected, got $status" >&2
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

expect_output_not_contains() {
  local desc="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$TMP/out.txt"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: did not expect output to contain '$needle'" >&2
    cat "$TMP/out.txt" >&2
  else
    PASS=$((PASS + 1))
  fi
}

check_json() {
  local desc="$1"
  local expected_mode="$2"
  shift 2
  local status=0
  set +e
  PATH="$FAKE_BIN:/usr/bin:/bin" bash "$VERIFY" "$@" >"$TMP/json.txt" 2>&1
  status=$?
  set -e
  # Validate JSON parses.
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/json.txt" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: output is not valid JSON" >&2
    cat "$TMP/json.txt" >&2
    return
  fi
  local mode
  mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("mode",""))' "$TMP/json.txt")"
  if [[ "$mode" == "$expected_mode" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: expected mode '$expected_mode', got '$mode'" >&2
    cat "$TMP/json.txt" >&2
  fi
  # Existing fields preserved.
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "blackhole" in d and "airpods" in d; assert "found" in d["blackhole"] and "rate_44100" in d["blackhole"]; assert "found" in d["airpods"] and "rate_48000" in d["airpods"]' "$TMP/json.txt" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: legacy JSON fields missing" >&2
    cat "$TMP/json.txt" >&2
  fi
  echo "$status" >"$TMP/json.status"
}

check_json_flag() {
  local desc="$1"
  local expr="$2"
  shift 2
  local flag_status=0
  set +e
  PATH="$FAKE_BIN:/usr/bin:/bin" bash "$VERIFY" "$@" >"$TMP/flag.json" 2>&1
  flag_status=$?
  set -e
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert ('"$expr"')' "$TMP/flag.json" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: JSON flag check failed ($expr)" >&2
    cat "$TMP/flag.json" >&2
  fi
  if [[ "$flag_status" -eq 1 ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc: expected json exit 1, got $flag_status" >&2
    cat "$TMP/flag.json" >&2
  fi
}

HAL_OK='Audio:

    Devices:

        APM44 Bridge:

            Manufacturer: APM44
            Output Channels: 2
            Current SampleRate: 44100

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Output Channels: 2
            Current SampleRate: 48000'

FALLBACK_OK='Audio:

    Devices:

        BlackHole 2ch:

            Manufacturer: Existential Audio
            Output Channels: 2
            Current SampleRate: 44100

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Output Channels: 2
            Current SampleRate: 48000'

APM44_WRONG='Audio:

    Devices:

        APM44 Bridge:

            Manufacturer: APM44
            Current SampleRate: 48000

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000'

AIRPODS_WRONG='Audio:

    Devices:

        APM44 Bridge:

            Manufacturer: APM44
            Current SampleRate: 44100

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 44100'

# Another device's rate must not satisfy APM44/AirPods/BlackHole.
CROSS_TALK='Audio:

    Devices:

        APM44 Bridge:

            Manufacturer: APM44
            Output Channels: 2

        Built-in Output:

            Manufacturer: Apple Inc.
            Current SampleRate: 44100

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000'

CROSS_TALK_AIRPODS='Audio:

    Devices:

        APM44 Bridge:

            Manufacturer: APM44
            Current SampleRate: 44100

        Built-in Output:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 44100'

CROSS_TALK_FALLBACK='Audio:

    Devices:

        BlackHole 2ch:

            Manufacturer: Existential Audio
            Output Channels: 2

        Built-in Output:

            Manufacturer: Apple Inc.
            Current SampleRate: 44100

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000'

# Available SampleRates inside the same block must not satisfy the check.
APM44_AVAILABLE_TRAP='Audio:

    Devices:

        APM44 Bridge:

            Available SampleRates: 44100, 48000
            Current SampleRate: 48000

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000'

BLACKHOLE_AVAILABLE_TRAP='Audio:

    Devices:

        BlackHole 2ch:

            Available SampleRates: 44100, 48000
            Current SampleRate: 48000

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000'

AIRPODS_AVAILABLE_TRAP='Audio:

    Devices:

        APM44 Bridge:

            Manufacturer: APM44
            Current SampleRate: 44100

        AirPods Max USB-C:

            Available SampleRates: 44100, 48000
            Current SampleRate: 44100'

QUOTED_OK='Audio:

    Devices:

        APM44 Bridge\Test "quoted":

            Manufacturer: APM44
            Current SampleRate: 44100

        AirPods Max USB-C:

            Manufacturer: Apple Inc.
            Current SampleRate: 48000'

# 1. HAL valid, no BlackHole -> default/--hal exit 0, --fallback exit 1.
set_profile "$HAL_OK"
expect_exit "hal-ok default exits 0" 0
expect_output_not_contains "hal-ok no misleading BlackHole FAIL" "FAIL: BlackHole"
expect_exit "hal-ok --hal exits 0" 0 --hal
expect_exit "hal-ok --fallback exits 1" 1 --fallback

# A Bluetooth endpoint at 48 kHz must not masquerade as the USB-C route.
set_airpods_device 48000 1651275109
expect_exit "Bluetooth-only AirPods fail HAL" 1 --hal
expect_output_contains "Bluetooth-only diagnosis" "Bluetooth does not satisfy the USB-C route"
check_json_flag "Bluetooth-only JSON fails USB check" 'd["airpods"]["usb_transport"] is False and d["airpods"]["rate_48000"] is False' --hal --json

saved_bridge_bin="$APM44_BRIDGE_BIN"
export APM44_BRIDGE_BIN="$TMP/missing-bridge"
expect_exit "missing Core Audio enumerator fails closed" 1 --hal
expect_output_contains "missing enumerator diagnosis" "cannot verify AirPods USB output"
export APM44_BRIDGE_BIN="$saved_bridge_bin"

# Core Audio may show the USB output even when system_profiler only lists Bluetooth.
set_profile 'Audio:

    Devices:

        APM44 Bridge:
            Current SampleRate: 44100

        AirPods Max von Nikolay:
            Output Channels: 2
            Current SampleRate: 48000
            Transport: Bluetooth'
expect_exit "USB output hidden from system_profiler still passes" 0 --hal
expect_output_contains "USB output named in result" "PASS: AirPods USB nominal 48000"

# 2. Fallback valid, no APM44 -> --fallback exit 0, default exit 1.
set_profile "$FALLBACK_OK"
expect_exit "fallback-ok --fallback exits 0" 0 --fallback
expect_exit "fallback-ok default exits 1" 1
expect_exit "fallback-ok --hal exits 1" 1 --hal

# 3. Wrong rates fail.
set_profile "$APM44_WRONG"
expect_exit "wrong apm44 rate --hal fails" 1 --hal
expect_exit "wrong apm44 rate default fails" 1

set_profile "$AIRPODS_WRONG"
set_airpods_device 44100 1970496032
expect_exit "wrong airpods rate --hal fails" 1 --hal
expect_exit "wrong airpods rate --fallback fails" 1 --fallback

# 4. Missing profile fails.
set_profile
expect_exit "missing profile default fails" 1
expect_exit "missing profile --hal fails" 1 --hal
expect_exit "missing profile --fallback fails" 1 --fallback

# 5. Cross-device leakage must not pass.
set_profile "$CROSS_TALK"
expect_exit "cross-talk apm44 without rate fails" 1 --hal

set_profile "$CROSS_TALK_AIRPODS"
set_airpods_device 44100 1970496032
expect_exit "cross-talk airpods without rate fails" 1 --hal

set_profile "$CROSS_TALK_FALLBACK"
expect_exit "cross-talk blackhole without rate fails" 1 --fallback

# 5b. Available rates in the same block must not satisfy the current-rate check.
set_profile "$APM44_AVAILABLE_TRAP"
expect_exit "available-rate trap apm44 fails --hal" 1 --hal
expect_exit "available-rate trap apm44 fails default" 1
check_json_flag "available-rate trap apm44 json false" 'd["apm44"]["rate_44100"] is False' --hal --json

set_profile "$BLACKHOLE_AVAILABLE_TRAP"
expect_exit "available-rate trap blackhole fails --fallback" 1 --fallback
check_json_flag "available-rate trap blackhole json false" 'd["blackhole"]["rate_44100"] is False' --fallback --json

set_profile "$AIRPODS_AVAILABLE_TRAP"
set_airpods_device 44100 1970496032
expect_exit "available-rate trap airpods fails --hal" 1 --hal
expect_exit "available-rate trap airpods fails --fallback" 1 --fallback
check_json_flag "available-rate trap airpods json false" 'd["airpods"]["rate_48000"] is False' --hal --json

# 5c. Names with quotes/backslashes must stay valid JSON.
set_profile "$QUOTED_OK"
expect_exit "quoted name hal passes" 0 --hal
check_json "quoted name json valid" "hal" --hal --json
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["apm44"]["found"] is True and d["apm44"]["rate_44100"] is True and "quoted" in d["apm44"]["name"] and "\\" in d["apm44"]["name"]' "$TMP/json.txt" 2>/dev/null; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: quoted name round-trips through JSON" >&2
  cat "$TMP/json.txt" >&2
fi

# 6. Unknown arguments fail with usage.
set_profile "$HAL_OK"
expect_exit "unknown arg fails" 2 --bogus
expect_output_contains "unknown arg prints usage" "Usage:"

# 7. JSON parses and reports selected mode.
set_profile "$HAL_OK"
check_json "json default reports hal" "hal" --json
check_json "json --hal reports hal" "hal" --hal --json

set_profile "$FALLBACK_OK"
check_json "json --fallback reports fallback" "fallback" --fallback --json

# JSON exit status still reflects mode.
set +e
set_profile "$HAL_OK"
PATH="$FAKE_BIN:/usr/bin:/bin" bash "$VERIFY" --hal --json >"$TMP/j.txt" 2>&1
s1=$?
PATH="$FAKE_BIN:/usr/bin:/bin" bash "$VERIFY" --fallback --json >"$TMP/j.txt" 2>&1
s2=$?
set -e
if [[ "$s1" -eq 0 && "$s2" -eq 1 ]]; then
  PASS=$((PASS + 2))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: json exit status must reflect mode (got $s1/$s2)" >&2
fi

echo "verify-devices tests: $PASS passed, $FAIL failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
echo "verify-devices tests: OK"
