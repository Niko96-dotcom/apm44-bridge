---
phase: 08-hardening-and-live-verification
plan: 02
subsystem: app
tags: [swift, catch2, latency, process-lifecycle]
requires:
  - phase: 08-hardening-and-live-verification
    provides: BridgeControlLoop.h and BridgeInputOverrun.h for tests
provides:
  - Stop escalation with pipe handler cleanup
  - HAL-effective latency UI and CLI args
  - test_hardening_audit regression suite
affects: [08-03]
tech-stack:
  added: [tests/test_hardening_audit.cpp]
  patterns: [effectiveTargetFillMs(halMode:), clearPipeHandlers]
key-files:
  created: [tests/test_hardening_audit.cpp]
  modified: [BridgeProcessManager.swift, LatencyPreset.swift, BridgeSettings.swift, MenuContentView.swift]
key-decisions:
  - "User stop calls initiateStop synchronously; escalation runs in background Task"
  - "HAL minimum 20 ms applies to Low and Balanced presets in HAL mode"
requirements-completed: [AUD-06, AUD-07, QA-02]
duration: 20min
completed: 2026-06-11
---

# Phase 8 Plan 02: App Lifecycle and Regression Tests Summary

**Stop escalation with handler cleanup, HAL-truthful latency labels, and Catch2 hardening audit suite**

## Performance

- **Duration:** ~20 min
- **Tasks:** 3 (+1 fix commit)
- **Files modified:** 7

## Accomplishments

- `clearPipeHandlers()` on termination and idle transition
- User/hotplug stop waits 5 s then SIGKILL
- `effectiveTargetFillMs(halMode:)` mirrors daemon `max(preset, 20)` clamp
- `test_hardening_audit` covers null-header shm, overrun, constants
- Stale shm coverage remains in `test_shm_stale_recovery` (QA-02)

## Task Commits

1. **Process handler cleanup** - `980c93f`, fix `543ca08`
2. **Latency UI truth** - `233c732`
3. **C++ regression tests** - `ac97905`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Synchronous initiateStop for user stop**
- **Found during:** Task 1 verification (CI Swift tests)
- **Issue:** `stop()` wrapped full async path in Task; tests saw wrong state race
- **Fix:** `initiateStop` runs synchronously; escalation in background Task
- **Commit:** `543ca08`

## Self-Check: PASSED

- test_hardening_audit.cpp: FOUND
- Commits 980c93f, 233c732, ac97905, 543ca08: FOUND

---
*Phase: 08-hardening-and-live-verification*
*Completed: 2026-06-11*
