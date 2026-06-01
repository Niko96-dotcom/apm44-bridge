#!/usr/bin/env bash
# QA-02: Verify DAW bounce/export remained 44100 Hz when project rate is 44.1.
# Monitoring path (bridge → AirPods @ 48 kHz) must not alter exported file sample rate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_RATE="44100"
JSON_MODE=0

usage() {
  cat <<'EOF'
Usage: validate-export-rate.sh [--help | --instructions | --check-file PATH [--json]]

QA-02 helper: confirm exported/bounced audio files are 44100 Hz when the DAW
project was set to 44.1 kHz.

Commands:
  --instructions   Print Logic + Ableton bounce steps (no hardware)
  --check-file PATH
                   Use macOS `afinfo` to assert file sample rate is 44100 Hz
  --json           With --check-file, emit JSON result on stdout
  --help           This message

Examples:
  bash scripts/validate-export-rate.sh --instructions
  bash scripts/validate-export-rate.sh --check-file ~/Desktop/mix.wav
  bash scripts/validate-export-rate.sh --check-file bounce.aiff --json

See docs/daw-matrix.md for full DAW validation matrix.
EOF
}

print_instructions() {
  cat <<'EOF'
=== QA-02 export rate validation ===

Principle: DAW output goes to BlackHole (MVP) or APM44 Bridge (production) for
monitoring only. Bounce/export uses the project sample rate (44100 Hz). The
bridge resamples to AirPods @ 48 kHz for listening — it does not change export.

--- Cubase Pro / Nuendo ---
1. Set project sample rate to 44100 Hz.
2. **Studio → Audio Connections**: output **APM44 Bridge**.
3. **Control Room**: Monitor 1 L/R device ports → APM44 Bridge (see docs/first-run-cubase.md).
4. Start APM44 Bridge menu bar app; confirm HAL routing mode.
5. **File → Export → Audio Mixdown** @ 44100 Hz.
6. Run: bash scripts/validate-export-rate.sh --check-file /path/to/mix.wav

--- Logic Pro ---
1. Set project sample rate to 44100 Hz.
2. Route monitoring output to BlackHole 2ch (MVP) or APM44 Bridge (production).
3. Start apm44-bridge or APM44 Bridge menu bar app; confirm monitoring works.
4. File → Bounce → Project or Section.
5. Sample rate: "Use project sample rate" (44100).
6. Export WAV or AIFF to a known path.
7. Run: bash scripts/validate-export-rate.sh --check-file /path/to/bounce.wav

--- Ableton Live ---
1. Preferences → Audio → Sample rate 44100 Hz.
2. Output: BlackHole 2ch (MVP) or APM44 Bridge (production).
3. Start bridge; confirm monitoring.
4. File → Export Audio/Video; sample rate 44100 Hz.
5. Run: bash scripts/validate-export-rate.sh --check-file /path/to/export.wav

--- Pass criteria ---
afinfo reports "44100" (or 44100.0) as the file sample rate. Exit code 0.

Full matrix: docs/daw-matrix.md
EOF
}

check_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: file not found: $path" >&2
    return 1
  fi
  if ! command -v afinfo >/dev/null 2>&1; then
    echo "FAIL: afinfo not found (macOS only)" >&2
    return 1
  fi

  local info rate_hz ok=0
  info="$(afinfo "$path" 2>/dev/null || true)"
  if [[ -z "$info" ]]; then
    echo "FAIL: afinfo could not read $path" >&2
    return 1
  fi

  # afinfo formats vary; match common sample rate lines
  rate_hz="$(echo "$info" | grep -Ei 'sample rate|Sample Rate' | head -1 | grep -Eo '[0-9]+(\.[0-9]+)?' | head -1 || true)"
  if [[ -z "$rate_hz" ]]; then
    echo "FAIL: could not parse sample rate from afinfo output" >&2
    echo "$info" >&2
    return 1
  fi

  # Accept 44100 or 44100.0 (integer compare via truncation)
  if [[ "${rate_hz%%.*}" == "$EXPECTED_RATE" ]]; then
    ok=1
  fi

  if [[ "$JSON_MODE" -eq 1 ]]; then
    printf '{"file":"%s","sample_rate_hz":%s,"expected_hz":%s,"pass":%s}\n' \
      "${path//\"/}" \
      "$rate_hz" \
      "$EXPECTED_RATE" \
      "$( [[ "$ok" -eq 1 ]] && echo true || echo false )"
  else
    if [[ "$ok" -eq 1 ]]; then
      echo "PASS: $path sample rate ${rate_hz} Hz (expected ${EXPECTED_RATE} Hz)"
    else
      echo "FAIL: $path sample rate ${rate_hz} Hz (expected ${EXPECTED_RATE} Hz)" >&2
      echo "hint: confirm DAW bounce used project rate 44100, not 48000" >&2
    fi
  fi

  [[ "$ok" -eq 1 ]]
}

ACTION=""
CHECK_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --instructions)
      ACTION=instructions
      shift
      ;;
    --check-file)
      ACTION=check
      CHECK_FILE="${2:-}"
      if [[ -z "$CHECK_FILE" ]]; then
        echo "error: --check-file requires a path" >&2
        exit 1
      fi
      shift 2
      ;;
    --json)
      JSON_MODE=1
      shift
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  usage
  exit 0
fi

case "$ACTION" in
  instructions)
    print_instructions
    ;;
  check)
    check_file "$CHECK_FILE"
    ;;
esac
