# Phase 1 verification: BlackHole Console Bridge

**Date:** 2026-06-01  
**Overall status:** `human_needed`

## Automated checks

| Check | Status | Notes |
|-------|--------|-------|
| `cmake -S . -B build` | passed | macOS 14+, CMake 3.28, Xcode CLT |
| `cmake --build build` | passed | `apm44-bridge` + unit tests |
| `ctest --test-dir build` | passed | 4/4 tests (audio_formats, device_enumerator, planar_ring, audio_converter_src) |
| `apm44-bridge --help` | passed | Documents `--input-device` / `--output-device` |
| `apm44-bridge --version` | passed | Prints `0.1.0` |
| RT IOProc logging scan | passed | No spdlog/NSLog/fprintf/cerr in `IoProcHandlers.cpp` |
| Single `AudioConverterNew` | passed | One instance in `AudioConverterSrc.cpp` |
| `bash -n scripts/verify-devices.sh` | passed | Shell syntax valid |
| Doc presence (`mvp-routing`, GPL note, Logic/Ableton) | passed | grep verification in plan 01-04 |
| `--print-config` in help | passed | |

## Hardware-dependent checks

| Check | Status | Notes |
|-------|--------|-------|
| `scripts/verify-devices.sh` PASS | human_needed | Requires BlackHole @ 44100 + AirPods @ 48000 on host |
| `apm44-bridge --preflight` exit 0 | human_needed | Same prerequisites |
| `apm44-bridge --list-devices` shows BlackHole | human_needed | |
| Live IOProc run until SIGINT | human_needed | Start bridge with valid devices |
| **440 Hz DAW tone audible on AirPods** | human_needed | Phase 1 success demo (plan 01-04 checkpoint) |

### Manual steps (440 Hz demo)

1. Install BlackHole 2ch v0.6.1+; set **44100 Hz** in Audio MIDI Setup.
2. Connect AirPods Max USB-C; set **48000 Hz** (do not force 44100).
3. `bash scripts/verify-devices.sh` → both PASS.
4. `./build/BridgeDaemon/apm44-bridge --preflight` → exit 0.
5. Run `./build/BridgeDaemon/apm44-bridge` (leave running).
6. Logic or Ableton: project **44100 Hz**, output **BlackHole 2ch**, play **440 Hz** test tone ~10 s.
7. Confirm audible, correctly pitched tone in AirPods; Ctrl+C bridge and note xrun count.
8. Resume GSD with `approved` or describe failure mode.

## Gaps / deferred

- No long-run (30+ min) stability test in CI (manual / Phase 5).
- `verify-devices.sh` uses `system_profiler` heuristics — may false-negative if profile text omits rate strings; use `--preflight` as source of truth.
- Drift control, menu bar UI, HAL driver: out of scope for Phase 1 (by design).

## Commit references

Recorded in plan SUMMARY files (`01-01-SUMMARY.md` … `01-04-SUMMARY.md`) after execution commits.
