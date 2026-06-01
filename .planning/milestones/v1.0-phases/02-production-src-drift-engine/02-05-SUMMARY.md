---
phase: 02-production-src-drift-engine
plan: 05
subsystem: audio-engine
tags: [bridge, cli]
requires:
  - phase: 02-02
    provides: ring fill metrics
  - phase: 02-03
    provides: DriftController
  - phase: 02-04
    provides: LibSamplerateSrc
provides:
  - Production BridgeEngine path with CLI tuning
affects: [02-06, phase-03]
tech-stack:
  added: []
  patterns: [input push-only, output pop+drift+SRC]
key-files:
  created: []
  modified: [BridgeDaemon/src/engine/BridgeEngine.h, BridgeDaemon/src/engine/BridgeEngine.cpp, BridgeDaemon/src/CliOptions.h, BridgeDaemon/src/CliOptions.cpp, BridgeDaemon/src/main.cpp, BridgeDaemon/CMakeLists.txt]
key-decisions:
  - "Overrun notify on ring push shortfall; underrun on pop/SRC failure"
  - "Legacy AudioConverter gated behind --legacy-converter"
requirements-completed: [ENG-02, ENG-03, ENG-04]
duration: 12min
completed: 2026-06-01
---

# Phase 2 Plan 05: BridgeEngine Integration Summary

**Default bridge path uses libsamplerate + drift PI; CLI exposes fill target, SRC quality, and legacy converter.**

## Accomplishments

- `BridgeEngineOptions` wired from CLI (`--target-fill-ms` 10–40, `--src-quality`, `--legacy-converter`)
- Output IOProc: fill → `drift_.update()` → `src_.setRatio()` → `src_.process()`
- Exit stats: fill_ms, ratio, ppm, underruns, overruns, xruns

## Deviations from Plan

None.

## Self-Check: PASSED
