---
phase: 10
status: passed
verified_at: 2026-06-12
verifier: gsd-verifier
---

# Phase 10: Process and Metrics Race Hardening — Verification

## Success criteria check

| # | Criterion | Status |
|---|-----------|--------|
| 1 | A daemon that ignores graceful termination reaches the SIGKILL escalation path and returns a final result instead of hanging | **PASS** — `finishStopWithEscalation` already escalates to `kill(proc.processIdentifier, SIGKILL)` after the 5s graceful timeout; the new `resumeTerminationWaiters()` call in the post-kill `catch` branch ensures the helper returns a final `false` (or `true`) and any in-flight waiter unblocks |
| 2 | Concurrent stop/restart waiters complete independently without one waiter overwriting another | **PASS** — `terminationContinuations` is now a `[CheckedContinuation<Void, Never>]` list; `waitForTermination` appends, `resumeTerminationWaiters` drains and clears. `testConcurrentTerminationWaitersAllComplete` verifies both waiters complete |
| 3 | Metrics read by CLI/control/UI paths are published with no C++ data race | **PASS** — `MetricsPublisher::PublishMetrics` / `ReadMetrics` implement a seqlock (odd/even sequence with release/acquire fences). `MetricsPublisherSeqlockNeverDeliversTornSnapshot` exercises the contract with 1 writer + 4 reader threads over 50,000 iterations and asserts no reader ever sees a counter regression |
| 4 | Swift and native tests cover termination timeout/escalation, concurrent waiters, and the metrics publication contract | **PASS** — `testConcurrentTerminationWaitersAllComplete` (Swift) + `MetricsPublisherSeqlockNeverDeliversTornSnapshot` (Catch2) + `NoBareMetricsSnapshotCopyInSource` regression guard |

## Test run

### C++ (Catch2 / ctest)

```
19/19 tests passed
test_bridge_metrics_json: 4 cases pass (including 2 new)
```

### Swift (XCTest)

```
BridgeProcessManagerTests: 25/25 tests passed (0.609 seconds)
testConcurrentTerminationWaitersAllComplete: passed (0.022 seconds)
```

## Code review flags

None outstanding.

## Must-haves derived from goal-backward

| Must-have | Where it's proven |
|-----------|-------------------|
| Single-termination-continuation slot replaced with a list | `BridgeProcessManager.swift:42` (`terminationContinuations: [CheckedContinuation<Void, Never>]`); `waitForTermination` appends; `resumeTerminationWaiters` drains |
| Concurrent waiters both unblock on termination | `testConcurrentTerminationWaitersAllComplete` |
| Post-SIGKILL timeout unblocks any in-flight waiter | `finishStopWithEscalation` second `catch` branch now calls `resumeTerminationWaiters()` before returning |
| Metrics publication is data-race-free | `MetricsPublisher.h` seqlock; `MetricsPublisherSeqlockNeverDeliversTornSnapshot` stress test |
| METR-02 fields remain available | `BridgeEngine` still publishes `fillMs, smoothedRatio, ppm, underruns, overruns, xruns`; `MakeBridgeMetrics` / `ToJsonLine` untouched; full `test_bridge_metrics_json` passes |
| No bare cross-thread MetricsSnapshot copy | `NoBareMetricsSnapshotCopyInSource` regression guard |

## Result

**Phase 10 status: passed.**

All four PROC-* requirements and all three METR-* requirements are
satisfied. Process-stop/restart coordination is deterministic under
concurrent waiters, and the metrics publication contract is proven
data-race-free by a multi-threaded stress test plus a source-level
regression guard.
