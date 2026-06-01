#!/usr/bin/env bash
# Pre-flight check: BlackHole @ 44100 Hz, AirPods-class output @ 48000 Hz.
# Read-only: system_profiler (+ optional SwitchAudioSource listing).
# Optional: brew install switchaudio-osx  (not required)
set -euo pipefail

JSON_MODE=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=1
fi

PROFILE="$(system_profiler SPAudioDataType 2>/dev/null || true)"
if [[ -z "$PROFILE" ]]; then
  echo "FAIL: could not read SPAudioDataType"
  exit 1
fi

blackhole_ok=0
airpods_ok=0
blackhole_name=""
airpods_name=""

if echo "$PROFILE" | grep -qi "BlackHole"; then
  blackhole_name="$(echo "$PROFILE" | grep -i "BlackHole" | head -1 | sed 's/^[[:space:]]*//')"
  if echo "$PROFILE" | grep -A20 -i "BlackHole" | grep -Eq "44100|44\.1"; then
    blackhole_ok=1
  fi
fi

if echo "$PROFILE" | grep -qi "AirPods"; then
  airpods_name="$(echo "$PROFILE" | grep -i "AirPods" | head -1 | sed 's/^[[:space:]]*//')"
  if echo "$PROFILE" | grep -A30 -i "AirPods" | grep -Eq "48000|48\.0"; then
    airpods_ok=1
  fi
fi

if [[ "$JSON_MODE" -eq 1 ]]; then
  printf '{"blackhole":{"found":%s,"rate_44100":%s,"name":"%s"},"airpods":{"found":%s,"rate_48000":%s,"name":"%s"}}\n' \
    "$( [[ -n "$blackhole_name" ]] && echo true || echo false )" \
    "$( [[ "$blackhole_ok" -eq 1 ]] && echo true || echo false )" \
    "${blackhole_name//\"/}" \
    "$( [[ -n "$airpods_name" ]] && echo true || echo false )" \
    "$( [[ "$airpods_ok" -eq 1 ]] && echo true || echo false )" \
    "${airpods_name//\"/}"
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

  if [[ -n "$airpods_name" ]]; then
    if [[ "$airpods_ok" -eq 1 ]]; then
      echo "PASS: AirPods nominal 48000 — $airpods_name"
    else
      echo "FAIL: AirPods found but not at 48000 Hz — open Audio MIDI Setup → AirPods Max USB-C → 48000 Hz (do not force 44100)"
    fi
  else
    echo "FAIL: AirPods output not found — connect AirPods Max USB-C"
  fi

  if command -v SwitchAudioSource >/dev/null 2>&1; then
    echo "info: SwitchAudioSource devices:"
    SwitchAudioSource -a || true
  fi
fi

if [[ "$blackhole_ok" -eq 1 && "$airpods_ok" -eq 1 ]]; then
  exit 0
fi
exit 1
