---
phase: 13-runtime-correctness-blockers
plan: 02
subsystem: core-audio-runtime
tags: [coreaudio, ioproc, realtime, spsc, catch2]
requires:
  - phase: 13-01
    provides: metrics publisher and JSON safety fixes
provides:
  - Shortest-channel non-interleaved input sizing
  - Started-vs-created IOProc cleanup for virtual-device output-start failures
  - Drop-new-input helper naming and dead helper cleanup
affects: [BridgeDaemon, Core Audio callbacks, realtime ring ownership]
tech-stack:
  added: []
  patterns:
    - Pure/source-level regression guards for Core Audio paths that are difficult to inject directly
    - Explicit started-vs-created IOProc cleanup state
key-files:
  created:
    - .planning/phases/13-runtime-correctness-blockers/13-02-SUMMARY.md
  modified:
    - BridgeDaemon/src/engine/BridgeEngine.cpp
    - BridgeDaemon/src/engine/BridgeEngine.h
    - BridgeDaemon/src/engine/IoProcHandlers.cpp
    - BridgeDaemon/src/engine/BridgeInputOverrun.h
    - tests/test_io_proc_callbacks.cpp
    - tests/test_planar_ring_buffer.cpp
    - tests/test_hardening_audit.cpp
key-decisions:
  - "Output-start cleanup tracks whether input/output IOProcs were actually started before stopping them."
  - "The overrun helper is named for drop-new-input behavior without changing the shipped policy."
patterns-established:
  - "Core Audio regression tests can mirror small callback computations when a live device is not required."
requirements-completed: [AUD-01, AUD-02, AUD-03, RT-01, RT-02]
duration: 18 min
completed: 2026-06-12
---

# Phase 13 Plan 02: Core Audio Edge Paths and Realtime Helper Cleanup Summary

**Core Audio callback edge cases are bounded and the realtime overrun helper now truthfully names drop-new-input behavior**

## Performance

- **Duration:** 18 min
- **Started:** 2026-06-12T12:28:00Z
- **Completed:** 2026-06-12T12:46:00Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- Updated non-interleaved input callback sizing to use the shortest channel buffer before clamping.
- Added regression coverage for mismatched non-interleaved input buffer sizes.
- Refactored IOProc cleanup so output-start failure distinguishes created procs from started procs and avoids null virtual input stops.
- Renamed `DropOldestThenPush` to `PushDroppingNewInput` and updated source/tests to match drop-new-input behavior.
- Removed the unused `WriteSilence` helper from `IoProcHandlers.cpp`.

## Task Commits

1. **Tasks 1-3: Non-interleaved input sizing, virtual-device cleanup, and realtime helper cleanup** - `561f49c` (fix)

**Plan metadata:** this summary commit.

## Files Created/Modified

- `BridgeDaemon/src/engine/BridgeEngine.cpp` - Added `cleanupIOProcs` and output-start failure cleanup using started state.
- `BridgeDaemon/src/engine/BridgeEngine.h` - Declared private IOProc cleanup helper.
- `BridgeDaemon/src/engine/IoProcHandlers.cpp` - Uses shortest non-interleaved input buffer and removes dead `WriteSilence`.
- `BridgeDaemon/src/engine/BridgeInputOverrun.h` - Renamed helper to `PushDroppingNewInput`.
- `tests/test_io_proc_callbacks.cpp` - Added mismatched input sizing regression.
- `tests/test_planar_ring_buffer.cpp` - Updated drop-new-input helper tests.
- `tests/test_hardening_audit.cpp` - Added virtual-device output-start failure source guard and updated helper usage.

## Decisions Made

- Used explicit `inputStarted` / `outputStarted` cleanup state rather than assuming created IOProc IDs are started.
- Kept the drop-new-input policy unchanged; this plan only corrected naming, comments, and tests.

## Deviations from Plan

The three tasks were committed in one cohesive code commit because the requested changes overlap in `BridgeEngine.cpp`, `IoProcHandlers.cpp`, and the hardening audit test. Splitting the same edited lines into separate commits would have left intermediate history in a non-building state.

---

**Total deviations:** 1 process deviation (commit grouping only).
**Impact on plan:** Implementation scope and verification were unchanged.

## Issues Encountered

- The first hardening audit source-guard test failed under CTest because the test binary runs from `build/`; the file reader now searches `""`, `"../"`, and `"../../"` prefixes.

## User Setup Required

None - no external service configuration required.

## Verification

```bash
grep -n 'std::min(b0Frames, b1Frames)' BridgeDaemon/src/engine/IoProcHandlers.cpp
grep -n 'mismatched non-interleaved input' tests/test_io_proc_callbacks.cpp
grep -n 'inputStarted' BridgeDaemon/src/engine/BridgeEngine.cpp
grep -n 'virtual-device output-start failure' tests/test_hardening_audit.cpp
grep -R 'PushDroppingNewInput' BridgeDaemon/src tests -n
cmake --build build --target test_io_proc_callbacks test_hardening_audit test_planar_ring_buffer
ctest --test-dir build -R 'test_io_proc_callbacks|test_hardening_audit|test_planar_ring_buffer' --output-on-failure
```

Result: all commands passed.

## Self-Check: PASSED

- Key files exist and contain the expected patterns.
- Targeted CMake build and Catch2 tests passed.
- Requirements completed: AUD-01, AUD-02, AUD-03, RT-01, RT-02.

## Next Phase Readiness

Phase 13 implementation is ready for phase-level code review, full regression gates, and verification.

---
*Phase: 13-runtime-correctness-blockers*
*Completed: 2026-06-12*
