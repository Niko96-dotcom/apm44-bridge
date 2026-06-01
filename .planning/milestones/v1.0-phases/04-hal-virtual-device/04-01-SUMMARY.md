---
phase: 04-hal-virtual-device
plan: 01
subsystem: driver
tags: [libASPL, submodule, cmake]

requires: []
provides: [aspl::libASPL]
affects: [04-03]

tech-stack:
  added: [libASPL v3.1.2]
  patterns: [add_subdirectory EXCLUDE_FROM_ALL]

key-files:
  created: [cmake/LibASPL.cmake, third_party/libASPL]
  modified: [CMakeLists.txt, third_party/README.md, .gitmodules]

decisions:
  - "Pin libASPL at tag v3.1.2 (MIT) via git submodule"

metrics:
  duration: 15min
  completed: 2026-06-01
---

# Phase 4 Plan 01: libASPL Submodule Summary

**libASPL v3.1.2 vendored and wired into root CMake for the HAL driver target.**

## Accomplishments

- Git submodule `third_party/libASPL` at **v3.1.2**
- `cmake/LibASPL.cmake` with `BUILD_TESTING=OFF`
- Root `CMakeLists.txt` includes LibASPL before `Driver/`

## Deviations

None.

## Self-Check: PASSED
