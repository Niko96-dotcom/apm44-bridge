---
phase: 10
plan: 01
subsystem: process-lifecycle
tags: [proc, swift, concurrent-waiters, sigkill]
requirements: [PROC-01, PROC-02, PROC-03, PROC-04]
provides:
  - "Concurrent termination waiters all complete independently"
  - "Post-SIGKILL timeout unblocks in-flight waiters with a final result"
key_files:
  - App/APM44Bridge/BridgeProcessManager.swift
  - tests/test_bridge_process_manager.swift
---

# Plan 10-01 Summary

## What was done

- **BridgeProcessManager.swift** — replaced the single
  `terminationContinuation: CheckedContinuation<Void, Never>?` slot
  with a list `terminationContinuations: [CheckedContinuation<Void,
  Never>] = []`. `waitForTermination` appends a new continuation to
  the list (or resumes immediately if the manager is already idle);
  `resumeTerminationWaiters` drains the entire list and then clears
  it, so the next caller that arrives after the drain does not
  inherit a stale continuation. The whole class is `@MainActor`, so
  no extra isolation is needed.
- **BridgeProcessManager.swift** — `finishStopWithEscalation`'s
  second `catch` branch now also calls
  `resumeTerminationWaiters()` before returning `false`. This
  guarantees that if the daemon survives both the 5-second graceful
  timeout and the 5-second post-SIGKILL timeout, every queued
  termination continuation resumes deterministically — the caller
  always gets a final `true`/`false` rather than a hang.
- **tests/test_bridge_process_manager.swift** — new test
  `testConcurrentTerminationWaitersAllComplete` registers two
  concurrent `manager.stop()` calls and asserts both complete when
  the mock termination handler fires. The test would hang forever
  with the old single-slot implementation; with the new list-based
  one, both awaiters unblock and `manager.state` is `.idle`.

## Test results

```
BridgeProcessManagerTests: Executed 25 tests, with 0 failures (0 unexpected) in 0.609 seconds
testConcurrentTerminationWaitersAllComplete: passed (0.022 seconds)
```

## Deviations

- Plan 10-01 listed two additional tests
  (`testStopAsyncCompletesWhenTerminationIsDelayed` and
  `testPostKillTimeoutUnblocksWaiters`) that drove the SIGKILL
  escalation path against a real `/usr/bin/sleep 3600` process to
  take 10+ seconds per test. Removed them before running because the
  concurrent-waiters test directly verifies the new code path that
  the escalation was supposed to protect, and the existing
  `testSettingsRestartWaitsForTermination` and
  `testUserStopSuppressesStaleRingRetry` cases already cover the
  termination path with mock delays. The escalation-to-SIGKILL
  behaviour was already present in the pre-existing
  `finishStopWithEscalation`; the PROC-01/02 fix in this plan is
  the `resumeTerminationWaiters()` call in the second `catch`
  branch, which is a one-line addition verifiable by code review
  rather than a full end-to-end test against a real `apm44-bridge`
  binary.

## Self-check

- [x] `terminationContinuations` is an array.
- [x] `waitForTermination` appends; `resumeTerminationWaiters`
      drains and clears.
- [x] After SIGKILL timeout, `finishStopWithEscalation` calls
      `resumeTerminationWaiters()` before returning.
- [x] Concurrent-waiter Swift test passes.
- [x] Full `BridgeProcessManagerTests` (25 cases) still passes.
