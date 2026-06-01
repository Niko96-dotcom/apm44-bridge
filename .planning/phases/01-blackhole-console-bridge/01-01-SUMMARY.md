---
phase: 01-blackhole-console-bridge
plan: 01
subsystem: infra
tags: [cmake, cpp20, core-audio, catch2]
requires: []
provides:
  - CMake monorepo with apm44_shared and apm44-bridge targets
  - Float32 stereo non-interleaved ASBD helpers @ 44100/48000
  - CLI skeleton with --help and device UID flags
affects: [01-02, 01-03, 01-04]
tech-stack:
  added: [CMake 3.28, Catch2 3.5.4, C++20]
  patterns: [Shared static lib + BridgeDaemon executable]
key-files:
  created:
    - CMakeLists.txt
    - Shared/include/apm44/AudioFormats.h
    - BridgeDaemon/src/CliOptions.cpp
    - tests/test_audio_formats.cpp
  modified: []
key-decisions:
  - "CMake-first build (not Xcode-primary) for agent-friendly CI"
requirements-completed: [ENG-05]
duration: 25min
completed: 2026-06-01
---

# Phase 1 Plan 01: CMake scaffold Summary

**CMake 3.28 monorepo with Shared ASBD helpers, Catch2 unit tests, and apm44-bridge CLI parsing --help/--version/device UIDs.**

## Task Commits

1. **Task 1–2: Root CMake + CLI + tests** — `bece906` (feat)

**Plan metadata:** (pending docs commit)

## Self-Check: PASSED

- CMakeLists.txt, Shared/, BridgeDaemon CLI, tests present
- Commit `bece906` found
