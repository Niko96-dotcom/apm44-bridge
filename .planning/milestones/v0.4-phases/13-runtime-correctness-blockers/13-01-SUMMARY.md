---
phase: 13-runtime-correctness-blockers
plan: 01
subsystem: runtime-metrics
tags: [metrics, atomics, json, catch2, realtime]
requires:
  - phase: v0.3
    provides: realtime callback hardening baseline and existing MetricsPublisher API
provides:
  - Race-free metrics publisher using atomic field storage
  - Bounded metrics JSON truncation behavior
  - Catch2 regression coverage for metrics JSON and publication contracts
affects: [BridgeDaemon, App metrics parser, release validation]
tech-stack:
  added: []
  patterns:
    - Atomic-field publication with sequence retry for realtime-safe snapshots
    - Fail-closed fixed-buffer serialization for release evidence output
key-files:
  created:
    - .planning/phases/13-runtime-correctness-blockers/13-01-SUMMARY.md
  modified:
    - BridgeDaemon/src/engine/MetricsPublisher.h
    - BridgeDaemon/src/engine/BridgeMetrics.cpp
    - tests/test_bridge_metrics_json.cpp
key-decisions:
  - "MetricsPublisher keeps the existing API but stores every payload field atomically."
  - "Metrics JSON returns a bounded fail-closed fallback on snprintf failure or truncation."
patterns-established:
  - "Metrics publication uses atomic scalar fields plus a sequence counter, avoiding cross-thread non-atomic struct copies."
requirements-completed: [METR-01, METR-02, METR-03, JSON-01, JSON-02]
duration: 14 min
completed: 2026-06-12
---

# Phase 13 Plan 01: Metrics Publication and JSON Safety Summary

**Atomic metrics publication and fail-closed metrics JSON serialization with targeted Catch2 regression coverage**

## Performance

- **Duration:** 14 min
- **Started:** 2026-06-12T12:13:34Z
- **Completed:** 2026-06-12T12:27:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Replaced `MetricsPublisherState`'s non-atomic `MetricsSnapshot` payload with atomic scalar fields and a sequence counter.
- Preserved the existing `PublishMetrics` / `ReadMetrics` API used by `BridgeEngine`.
- Made `BridgeMetrics::ToJsonLine` return a bounded fallback when `snprintf` fails or would truncate.
- Added a long `src_quality` regression test and strengthened normal metrics field assertions.

## Task Commits

1. **Task 1: Replace non-atomic MetricsSnapshot publication with a race-free publisher** - `2fafa35` (fix)
2. **Task 2: Make BridgeMetrics JSON truncation fail closed without overread** - `ce00a2c` (fix)

## Files Created/Modified

- `BridgeDaemon/src/engine/MetricsPublisher.h` - Atomic metrics field storage with sequence retry reads.
- `BridgeDaemon/src/engine/BridgeMetrics.cpp` - Fail-closed truncation handling in `ToJsonLine`.
- `tests/test_bridge_metrics_json.cpp` - Normal field coverage, long quality truncation regression, and updated publisher contract text.

## Decisions Made

- Kept the existing metrics publisher function API to minimize churn in `BridgeEngine`.
- Used a bounded fallback (`{}`) rather than dynamic JSON allocation for truncation because release evidence needs safety more than preserving impossible oversized field values.

## Deviations from Plan

None - plan executed exactly as written.

---

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope change.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Verification

```bash
grep -n 'std::atomic<double>' BridgeDaemon/src/engine/MetricsPublisher.h
grep -n 'written >= static_cast<int>(sizeof(buffer))' BridgeDaemon/src/engine/BridgeMetrics.cpp
grep -n 'longQuality' tests/test_bridge_metrics_json.cpp
cmake --build build --target test_bridge_metrics_json
ctest --test-dir build -R test_bridge_metrics_json --output-on-failure
```

Result: all commands passed.

## Self-Check: PASSED

- Key files exist and contain the expected patterns.
- Targeted Catch2 build and test passed.
- Requirements completed: METR-01, METR-02, METR-03, JSON-01, JSON-02.

## Next Phase Readiness

Ready for Plan 13-02. It can build on the metrics fix and focus on Core Audio edge paths plus realtime helper cleanup.

---
*Phase: 13-runtime-correctness-blockers*
*Completed: 2026-06-12*
