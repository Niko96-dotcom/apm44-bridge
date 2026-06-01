---
phase: 02-production-src-drift-engine
plan: 03
subsystem: audio-engine
tags: [drift, pi-controller]
requires: []
provides:
  - DriftController with ±500 ppm clamp and ratio smoothing
affects: [02-05, 02-06]
tech-stack:
  added: []
  patterns: [PI on ring fill error]
key-files:
  created: [Shared/include/apm44/DriftController.h, Shared/src/DriftController.cpp, tests/test_drift_controller.cpp]
  modified: [Shared/CMakeLists.txt, tests/CMakeLists.txt]
key-decisions:
  - "PI gains as compile-time constants; soak may retune"
requirements-completed: [ENG-04]
duration: 10min
completed: 2026-06-01
---

# Phase 2 Plan 03: DriftController Summary

**PI drift controller maps ring fill error to bounded ppm adjustment on nominal 48000/44100 SRC ratio.**

## Accomplishments

- RT-safe `update()` (no alloc/locks/I/O)
- Underrun/overrun counter API for engine metrics
- Catch2 tests for clamp, sign, and counters

## Deviations from Plan

None.

## Self-Check: PASSED
