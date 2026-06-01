---
phase: 02-production-src-drift-engine
plan: 06
subsystem: testing
tags: [soak, qa-01]
requires:
  - phase: 02-05
    provides: production engine components
provides:
  - apm44-soak offline harness
  - docs/soak-test.md
  - scripts/ci-soak.sh
affects: [phase-03, phase-05]
tech-stack:
  added: []
  patterns: [block-rate simulated soak, not wall-clock spin]
key-files:
  created: [BridgeDaemon/src/tools/SoakHarness.h, BridgeDaemon/src/tools/SoakHarness.cpp, BridgeDaemon/src/tools/apm44_soak_main.cpp, tests/test_soak_offline.cpp, docs/soak-test.md, scripts/ci-soak.sh]
  modified: [BridgeDaemon/CMakeLists.txt, tests/CMakeLists.txt]
key-decisions:
  - "Soak simulates audio-time blocks (~48000 Hz) instead of tight wall-clock loop"
requirements-completed: [QA-01]
duration: 14min
completed: 2026-06-01
---

# Phase 2 Plan 06: Soak Harness Summary

**Offline clock-skew soak (`apm44-soak`) validates drift+SRC stability; human 30+ min procedure documented.**

## Accomplishments

- `RunSoakHarness()` reuses ring, drift, and libsamplerate (no HAL)
- `apm44-soak --duration-sec` / `--skew-ppm` / `--target-fill-ms`
- CI script: build + `ctest -R soak` + 60 s soak
- `docs/soak-test.md` for full QA-01 listening test

## Deviations from Plan

### Checkpoint

**human-verify (plan 02-06):** Auto-approved per executor `--no-transition` — doc reviewed in automation; user may still run 30+ min DAW soak per `docs/soak-test.md`.

## Self-Check: PASSED
