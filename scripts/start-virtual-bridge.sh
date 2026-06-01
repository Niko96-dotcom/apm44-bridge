#!/usr/bin/env bash
# Start apm44-bridge in HAL virtual-device mode (Cubase → APM44 Bridge → AirPods).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${APM44_BRIDGE_BIN:-$ROOT/build/BridgeDaemon/apm44-bridge}"

if [[ ! -x "$BIN" ]]; then
  echo "error: build first: cmake --build build --target apm44-bridge" >&2
  exit 1
fi

OUT_UID="${1:-}"
if [[ -z "$OUT_UID" ]]; then
  OUT_UID="$("$BIN" --list-devices | awk -F'\t' '
    $2 ~ /AirPods/ && $4 ~ /O/ {
      if ($3 + 0 != 48000) {
        print "warn: AirPods at " $3 " Hz — set 48000 in Audio MIDI Setup" > "/dev/stderr"
      }
      print $1
      exit
    }')"
  if [[ -n "$OUT_UID" ]]; then
    echo "Using AirPods output: $OUT_UID"
  else
    echo "error: AirPods not found. Connect AirPods Max with USB-C cable (menu bar should show USB-Audio)." >&2
    echo "  Then run: $0" >&2
    echo "  Or pass your UID from --list-devices:" >&2
    echo "  $0 \"90-62-3F-A3-52-03:output\"" >&2
    "$BIN" --list-devices
    exit 1
  fi
fi

exec "$BIN" --virtual-device --output-device "$OUT_UID"
