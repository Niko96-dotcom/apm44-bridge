#!/usr/bin/env bash
# Pre-flight check: route-specific hardware sample rates.
# HAL production (default): APM44 Bridge @ 44100 Hz + AirPods-class output @ 48000 Hz.
# Legacy fallback (--fallback): BlackHole @ 44100 Hz + AirPods @ 48000 Hz.
# Read-only: system_profiler, bridge Core Audio enumeration, and optional
# SwitchAudioSource listing. The enumerator also sees USB outputs omitted by
# system_profiler while their AudioBox is unacquired.
# Optional: brew install switchaudio-osx  (not required)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_BIN="${APM44_BRIDGE_BIN:-}"
if [[ -z "$BRIDGE_BIN" ]]; then
  if [[ -x "$ROOT/build/BridgeDaemon/apm44-bridge" ]]; then
    BRIDGE_BIN="$ROOT/build/BridgeDaemon/apm44-bridge"
  else
    BRIDGE_BIN="/Applications/APM44 Bridge.app/Contents/MacOS/apm44-bridge"
  fi
fi

MODE="hal"
JSON_MODE=0

usage() {
  cat <<'EOF'
Usage: verify-devices.sh [--hal|--fallback] [--json]
  --hal       APM44 Bridge @ 44100 Hz + AirPods USB @ 48000 Hz (default)
  --fallback  BlackHole @ 44100 Hz + AirPods USB @ 48000 Hz (legacy fallback)
  --json      machine-readable output (valid JSON, includes selected mode)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hal)
      MODE="hal"
      shift
      ;;
    --fallback)
      MODE="fallback"
      shift
      ;;
    --json)
      JSON_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

PROFILE="$(system_profiler SPAudioDataType 2>/dev/null || true)"
if [[ -z "$PROFILE" ]]; then
  if [[ "$JSON_MODE" -eq 1 ]]; then
    printf '{"mode":"%s","error":"could not read SPAudioDataType"}\n' "$MODE"
  else
    echo "FAIL: could not read SPAudioDataType"
  fi
  exit 1
fi

apm44_ok=0
apm44_found=0
apm44_name=""
blackhole_ok=0
blackhole_found=0
blackhole_name=""
airpods_ok=0
airpods_found=0
airpods_name=""

RATE_44100_PAT='44100|44[.,]1'
RATE_48000_PAT='48000|48[.,]0'

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# True only when an explicit current/nominal rate line carries the wanted rate.
# Available SampleRates or unrelated numbers must not satisfy the check;
# a missing current/nominal line fails.
has_current_rate() {
  printf '%s' "$1" | grep -Ei '(current|nominal).*rate|rate.*(current|nominal)' | grep -Eq "$2"
}

current_device=""
current_block=""

flush_block() {
  if [[ -z "$current_device" ]]; then
    return 0
  fi
  local lname
  lname="$(printf '%s' "$current_device" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lname" == *"apm44"* ]]; then
    if [[ "$apm44_found" -eq 0 ]]; then
      apm44_name="$current_device"
    fi
    apm44_found=1
    if has_current_rate "$current_block" "$RATE_44100_PAT"; then
      apm44_ok=1
      apm44_name="$current_device"
    fi
  fi
  if [[ "$lname" == *"blackhole"* ]]; then
    if [[ "$blackhole_found" -eq 0 ]]; then
      blackhole_name="$current_device"
    fi
    blackhole_found=1
    if has_current_rate "$current_block" "$RATE_44100_PAT"; then
      blackhole_ok=1
      blackhole_name="$current_device"
    fi
  fi
  if [[ "$lname" == *"airpods"* ]]; then
    if [[ "$airpods_found" -eq 0 ]]; then
      airpods_name="$current_device"
    fi
    airpods_found=1
    if has_current_rate "$current_block" "$RATE_48000_PAT"; then
      airpods_ok=1
      airpods_name="$current_device"
    fi
  fi
  return 0
}

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]*[^:]+:[[:space:]]*$ ]]; then
    flush_block
    current_device="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/:[[:space:]]*$//')"
    current_block=""
  else
    current_block+=$'\n'"$line"
  fi
done <<<"$PROFILE"
flush_block

# system_profiler may list only the Bluetooth endpoint while a USB AirPods
# output is present in Core Audio. Inspect the actual output transport instead.
usb_airpods_found=0
usb_airpods_name=""
usb_probe_error=""
airpods_ok=0
if [[ ! -x "$BRIDGE_BIN" ]]; then
  usb_probe_error="apm44-bridge device enumerator missing at $BRIDGE_BIN"
elif ! DEVICE_LIST="$("$BRIDGE_BIN" --list-devices 2>/dev/null)"; then
  usb_probe_error="apm44-bridge --list-devices failed"
else
  USB_ROWS="$(printf '%s\n' "$DEVICE_LIST" | awk -F '\t' '
    (tolower($1) ~ /airpods/ || tolower($2) ~ /airpods/) &&
    $4 ~ /O/ && $5 == 1 && $6 >= 2 && $8 == 1970496032 {
      print $2 "\t" $3
    }
  ')"
  while IFS=$'\t' read -r name rate; do
    [[ -n "$name" ]] || continue
    usb_airpods_found=1
    usb_airpods_name="$name"
    if [[ "$rate" == "48000" ]]; then
      airpods_ok=1
      airpods_name="$name"
      break
    fi
  done <<<"$USB_ROWS"
fi

# A Bluetooth output at 48 kHz is not the documented USB-C route.
if [[ "$usb_airpods_found" -eq 0 ]]; then
  airpods_ok=0
else
  airpods_found=1
  airpods_name="$usb_airpods_name"
fi

if [[ "$JSON_MODE" -eq 1 ]]; then
  printf '{"mode":"%s","apm44":{"found":%s,"rate_44100":%s,"name":"%s"},"blackhole":{"found":%s,"rate_44100":%s,"name":"%s"},"airpods":{"found":%s,"usb_transport":%s,"rate_48000":%s,"name":"%s"}}\n' \
    "$MODE" \
    "$( [[ -n "$apm44_name" ]] && echo true || echo false )" \
    "$( [[ "$apm44_ok" -eq 1 ]] && echo true || echo false )" \
    "$(json_escape "$apm44_name")" \
    "$( [[ -n "$blackhole_name" ]] && echo true || echo false )" \
    "$( [[ "$blackhole_ok" -eq 1 ]] && echo true || echo false )" \
    "$(json_escape "$blackhole_name")" \
    "$( [[ -n "$airpods_name" ]] && echo true || echo false )" \
    "$( [[ "$usb_airpods_found" -eq 1 ]] && echo true || echo false )" \
    "$( [[ "$airpods_ok" -eq 1 ]] && echo true || echo false )" \
    "$(json_escape "$airpods_name")"
else
  if [[ "$MODE" == "hal" ]]; then
    if [[ -n "$apm44_name" ]]; then
      if [[ "$apm44_ok" -eq 1 ]]; then
        echo "PASS: APM44 Bridge nominal 44100 — $apm44_name"
      else
        echo "FAIL: APM44 Bridge found but not at 44100 Hz — open Audio MIDI Setup → APM44 Bridge → 44100 Hz"
      fi
    else
      echo "FAIL: APM44 Bridge not found — install the APM44 Bridge HAL driver (BlackHole alone does not satisfy --hal)"
    fi

    if [[ "$airpods_ok" -eq 1 ]]; then
      echo "PASS: AirPods USB nominal 48000 — $airpods_name"
    elif [[ "$usb_airpods_found" -eq 1 ]]; then
      echo "FAIL: AirPods USB found but not at 48000 Hz — open Audio MIDI Setup → AirPods Max USB-C → 48000 Hz"
    elif [[ -n "$usb_probe_error" ]]; then
      echo "FAIL: cannot verify AirPods USB output — $usb_probe_error"
    elif [[ "$airpods_found" -eq 1 ]]; then
      echo "FAIL: AirPods found, but no USB output — Bluetooth does not satisfy the USB-C route"
    else
      echo "FAIL: AirPods output not found — connect AirPods Max USB-C"
    fi

    if [[ -n "$blackhole_name" ]]; then
      echo "info: BlackHole present ($blackhole_name) — optional, not required for HAL route"
    else
      echo "info: BlackHole not present — optional, not required for HAL route"
    fi
  else
    if [[ -n "$blackhole_name" ]]; then
      if [[ "$blackhole_ok" -eq 1 ]]; then
        echo "PASS: BlackHole nominal 44100 — $blackhole_name"
      else
        echo "FAIL: BlackHole found but not at 44100 Hz — open Audio MIDI Setup → BlackHole 2ch → 44100 Hz"
      fi
    else
      echo "FAIL: BlackHole not found — install BlackHole 2ch v0.6.1+ from https://github.com/ExistentialAudio/BlackHole/releases"
    fi

    if [[ "$airpods_ok" -eq 1 ]]; then
      echo "PASS: AirPods USB nominal 48000 — $airpods_name"
    elif [[ "$usb_airpods_found" -eq 1 ]]; then
      echo "FAIL: AirPods USB found but not at 48000 Hz — open Audio MIDI Setup → AirPods Max USB-C → 48000 Hz"
    elif [[ -n "$usb_probe_error" ]]; then
      echo "FAIL: cannot verify AirPods USB output — $usb_probe_error"
    elif [[ "$airpods_found" -eq 1 ]]; then
      echo "FAIL: AirPods found, but no USB output — Bluetooth does not satisfy the USB-C route"
    else
      echo "FAIL: AirPods output not found — connect AirPods Max USB-C"
    fi

    if [[ -n "$apm44_name" ]]; then
      echo "info: APM44 Bridge present ($apm44_name) — not required for fallback route"
    fi
  fi

  if command -v SwitchAudioSource >/dev/null 2>&1; then
    echo "info: SwitchAudioSource devices:"
    SwitchAudioSource -a || true
  fi
fi

if [[ "$MODE" == "hal" ]]; then
  if [[ "$apm44_ok" -eq 1 && "$airpods_ok" -eq 1 ]]; then
    exit 0
  fi
  exit 1
else
  if [[ "$blackhole_ok" -eq 1 && "$airpods_ok" -eq 1 ]]; then
    exit 0
  fi
  exit 1
fi
