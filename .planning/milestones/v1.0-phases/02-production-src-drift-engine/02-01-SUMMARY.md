---
phase: 02-production-src-drift-engine
plan: 01
subsystem: audio-engine
tags: [libsamplerate, cmake, src]
requires: []
provides:
  - Static libsamplerate 0.2.2 CMake target
  - Offline SRC smoke test
affects: [02-04, 02-05, 02-06]
tech-stack:
  added: [libsamplerate 0.2.2]
  patterns: [FetchContent/submodule pin]
key-files:
  created: [cmake/Libsamplerate.cmake, third_party/README.md, tests/test_libsamplerate_smoke.cpp]
  modified: [CMakeLists.txt, tests/CMakeLists.txt]
key-decisions:
  - "Pin libsamplerate 0.2.2; FetchContent fallback if submodule missing"
requirements-completed: [ENG-02]
duration: 15min
completed: 2026-06-01
---

# Phase 2 Plan 01: Vendor libsamplerate Summary

**Static libsamplerate 0.2.2 integrated into CMake with an offline `src_process` smoke test.**

## Accomplishments

- `cmake/Libsamplerate.cmake` builds static `samplerate::samplerate`
- `third_party/libsamplerate` at tag 0.2.2 (submodule + `.gitmodules`)
- Catch2 smoke test validates nominal 44.1→48 ratio

## Deviations from Plan

None.

## Self-Check: PASSED
