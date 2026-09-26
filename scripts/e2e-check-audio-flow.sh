#!/usr/bin/env bash
# Prove audio flows through the APM44 Bridge virtual device without listening.
# Re-resolves the device id from `say -a '?'`, samples --shm-status, plays
# nearly-silent speech covering --seconds, samples again and checks progress.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: e2e-check-audio-flow.sh [--seconds 3] [--helper <path>] [--device-name "APM44 Bridge"]

Re-resolves the device id from `say -a '?'` (ids change after a Core Audio
reload), samples <helper> --shm-status, plays
`say -a <id> "[[volm 0.02]] ..."` long enough to cover --seconds, samples again.

PASS only if all hold: shm_status=ok; daemon_ready=1; write_index and
read_index each advanced by >= seconds*44100*0.5; producer_dropped_frames did
not increase. Prints one line per check (PASS/FAIL with numbers) and exits
non-zero on failure.
USAGE
}

e2e_audio_get_value() {
  local text="$1"
  local key="$2"
  printf '%s\n' "$text" | sed -n "s/^${key}=//p" | head -n 1 | tr -d '\r'
}

e2e_audio_is_uint() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# Pure decision: call with two canned status texts and seconds.
# Prints one PASS/FAIL line per check, returns 0 only if all pass.
e2e_audio_flow_check_texts() {
  local before="$1"
  local after="$2"
  local seconds="$3"
  local threshold
  threshold="$(awk "BEGIN { printf \"%d\", ($seconds * 22050) }" 2>/dev/null || echo "")"
  if [[ -z "$threshold" ]]; then
    threshold=$((seconds * 22050))
  fi

  local b_shm a_shm b_ready a_ready b_w a_w b_r a_r b_d a_d
  b_shm="$(e2e_audio_get_value "$before" "shm_status")"
  a_shm="$(e2e_audio_get_value "$after" "shm_status")"
  b_ready="$(e2e_audio_get_value "$before" "daemon_ready")"
  a_ready="$(e2e_audio_get_value "$after" "daemon_ready")"
  b_w="$(e2e_audio_get_value "$before" "write_index")"
  a_w="$(e2e_audio_get_value "$after" "write_index")"
  b_r="$(e2e_audio_get_value "$before" "read_index")"
  a_r="$(e2e_audio_get_value "$after" "read_index")"
  b_d="$(e2e_audio_get_value "$before" "producer_dropped_frames")"
  a_d="$(e2e_audio_get_value "$after" "producer_dropped_frames")"

  local fail=0

  if [[ "$b_shm" == "ok" && "$a_shm" == "ok" ]]; then
    echo "CHECK shm_status: PASS (before=$b_shm after=$a_shm)"
  else
    echo "CHECK shm_status: FAIL (before=${b_shm:-<empty>} after=${a_shm:-<empty>}, expected ok)"
    fail=1
  fi

  if [[ "$b_ready" == "1" && "$a_ready" == "1" ]]; then
    echo "CHECK daemon_ready: PASS (before=$b_ready after=$a_ready)"
  else
    echo "CHECK daemon_ready: FAIL (before=${b_ready:-<empty>} after=${a_ready:-<empty>}, expected 1)"
    fail=1
  fi

  if e2e_audio_is_uint "$b_w" && e2e_audio_is_uint "$a_w"; then
    local diff_w=$((a_w - b_w))
    if [[ "$diff_w" -ge "$threshold" ]]; then
      echo "CHECK write_index: PASS (before=$b_w after=$a_w diff=$diff_w threshold=$threshold)"
    else
      echo "CHECK write_index: FAIL (before=$b_w after=$a_w diff=$diff_w threshold=$threshold)"
      fail=1
    fi
  else
    echo "CHECK write_index: FAIL (before=${b_w:-<empty>} after=${a_w:-<empty>} threshold=$threshold, non-numeric)"
    fail=1
  fi

  if e2e_audio_is_uint "$b_r" && e2e_audio_is_uint "$a_r"; then
    local diff_r=$((a_r - b_r))
    if [[ "$diff_r" -ge "$threshold" ]]; then
      echo "CHECK read_index: PASS (before=$b_r after=$a_r diff=$diff_r threshold=$threshold)"
    else
      echo "CHECK read_index: FAIL (before=$b_r after=$a_r diff=$diff_r threshold=$threshold)"
      fail=1
    fi
  else
    echo "CHECK read_index: FAIL (before=${b_r:-<empty>} after=${a_r:-<empty>} threshold=$threshold, non-numeric)"
    fail=1
  fi

  if e2e_audio_is_uint "$b_d" && e2e_audio_is_uint "$a_d"; then
    if [[ "$a_d" -le "$b_d" ]]; then
      echo "CHECK producer_dropped_frames: PASS (before=$b_d after=$a_d)"
    else
      echo "CHECK producer_dropped_frames: FAIL (before=$b_d after=$a_d, must not increase)"
      fail=1
    fi
  else
    echo "CHECK producer_dropped_frames: FAIL (before=${b_d:-<empty>} after=${a_d:-<empty>}, non-numeric)"
    fail=1
  fi

  if [[ "$fail" -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

e2e_audio_flow_check_files() {
  local bf="$1"
  local af="$2"
  local secs="$3"
  local bt at
  bt="$(cat "$bf")"
  at="$(cat "$af")"
  e2e_audio_flow_check_texts "$bt" "$at" "$secs"
}

if [[ "${E2E_AUDIO_FLOW_LIB_ONLY:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

SECONDS_N="3"
HELPER_ARG=""
DEVICE_NAME="APM44 Bridge"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --seconds)
      SECONDS_N="${2:-}"
      shift 2
      ;;
    --helper)
      HELPER_ARG="${2:-}"
      shift 2
      ;;
    --device-name)
      DEVICE_NAME="${2:-}"
      shift 2
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

HELPER=""
if [[ -n "$HELPER_ARG" ]]; then
  HELPER="$HELPER_ARG"
elif [[ -n "${APM44_E2E_HELPER:-}" ]]; then
  HELPER="$APM44_E2E_HELPER"
else
  HELPER="/Applications/APM44 Bridge.app/Contents/MacOS/apm44-bridge"
fi
SAY_CMD="${APM44_E2E_SAY:-say}"

RUN_DIR="$(mktemp -d)"
echo "run dir: $RUN_DIR"
cleanup() {
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

if [[ ! -x "$HELPER" ]]; then
  echo "error: helper not executable at $HELPER" >&2
  exit 1
fi

SAY_LIST="$("$SAY_CMD" -a '?' 2>&1 || true)"
DEVICE_ID="$(printf '%s\n' "$SAY_LIST" | grep -F "$DEVICE_NAME" | head -n 1 | awk '{print $1}' || true)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "CHECK device: FAIL (device '$DEVICE_NAME' not found in say -a '?')" >&2
  printf '%s\n' "$SAY_LIST" >&2 || true
  exit 1
fi
echo "device: $DEVICE_NAME id=$DEVICE_ID"

"$HELPER" --shm-status >"$RUN_DIR/before.txt" 2>"$RUN_DIR/before.err" || {
  echo "CHECK shm_status: FAIL (before sample failed)" >&2
  cat "$RUN_DIR/before.err" >&2 || true
  exit 1
}

REPEAT=$((SECONDS_N * 2 + 2))
if [[ "$REPEAT" -lt 4 ]]; then
  REPEAT=4
fi
TEXT=""
i=0
while [[ "$i" -lt "$REPEAT" ]]; do
  TEXT="${TEXT}audio flow verification test. "
  i=$((i + 1))
done

START="$(date +%s)"
"$SAY_CMD" -a "$DEVICE_ID" "[[volm 0.02]] $TEXT" >/dev/null 2>&1 || {
  echo "warn: say playback failed, continuing to after-sample" >&2
}
END="$(date +%s)"
ELAPSED=$((END - START))
if [[ "$ELAPSED" -lt "$SECONDS_N" ]]; then
  sleep $((SECONDS_N - ELAPSED))
fi

"$HELPER" --shm-status >"$RUN_DIR/after.txt" 2>"$RUN_DIR/after.err" || {
  echo "CHECK shm_status: FAIL (after sample failed)" >&2
  cat "$RUN_DIR/after.err" >&2 || true
  exit 1
}

if e2e_audio_flow_check_files "$RUN_DIR/before.txt" "$RUN_DIR/after.txt" "$SECONDS_N"; then
  echo "audio flow: PASS"
  exit 0
else
  echo "audio flow: FAIL" >&2
  exit 1
fi
