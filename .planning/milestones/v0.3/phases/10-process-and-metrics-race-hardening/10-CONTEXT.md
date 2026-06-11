# Phase 10: Process and Metrics Race Hardening - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous)

<domain>
## Phase Boundary

Process-stop/restart coordination in `BridgeProcessManager` is deterministic
under timeout and cross-caller access, and metrics publication in
`BridgeEngine` is data-race-free. Two distinct sub-domains:

1. **Process lifecycle (PROC-01..PROC-04)** — termination escalation to
   SIGKILL after the graceful timeout, no hang when the daemon ignores
   SIGTERM; concurrent stop/restart waiters all complete independently
   without one overwriting another; Swift lifecycle tests cover the
   paths.
2. **Metrics race hardening (METR-01..METR-03)** — metrics published from
   realtime/control paths are read through a C++ data-race-free
   mechanism; underrun/overrun/xrun/fill/ratio/ppm remain available to
   CLI JSON and the app UI; tests or source-level assertions prove no
   plain cross-thread `MetricsSnapshot` copy.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion. The constraints
are locked by REQUIREMENTS.md (PROC-01..PROC-04, METR-01..METR-03):

- Stop escalation must reach SIGKILL after the graceful timeout when
  the daemon is still running, and return a final result (no hang).
- Concurrent termination waiters must complete independently — no
  overwrite, no swallowed result.
- The metrics publication must be a C++ data-race-free mechanism
  (seqlock, atomics, or RCU) — not a plain `MetricsSnapshot` copy.
- The same metrics values (underrun, overrun, xrun, fill, ratio, ppm)
  must remain available to CLI JSON output and the Swift app UI.
- Swift and native tests must cover the escalation, concurrent waiters,
  and metrics publication contract.

### Discovered Code Reality

- `BridgeProcessManager` (App/APM44Bridge/BridgeProcessManager.swift)
  has a single `terminationContinuation: CheckedContinuation<Void,
  Never>?` slot. Two concurrent `await waitForTermination()` callers
  race to overwrite each other — exactly the PROC-03 violation.
- `BridgeEngine` (BridgeDaemon/src/engine/BridgeEngine.cpp lines
  165-188) already implements a seqlock (odd/even `metricsSeq_` with
  release/acquire fences) around `metricsSnapshot_`. This is
  data-race-free per C++11 atomics semantics. METR-01 is satisfied;
  the missing piece is an explicit test or source-level assertion
  proving the publication contract (METR-03).

### Selected Approach

- **PROC-03 fix**: replace the single `terminationContinuation` slot
  with an array (or set) of continuations. `waitForTermination` appends
  a new continuation; `resumeTerminationWaiters` resumes all of them
  and clears the array. Use a serial queue / MainActor to keep it
  race-free.
- **PROC-01/02 fix**: `finishStopWithEscalation` already escalates to
  SIGKILL on timeout, but it also needs to (a) reset the timeout
  clock after the kill and (b) not block forever if the second
  `waitForTermination` itself never resumes. The cleanest pattern:
  after SIGKILL, give one more bounded wait, then forcibly clear the
  process state and return `false` — `transitionToIdle()` will resume
  all pending waiters. The current code already returns `false` in
  the catch branch (line 578) but the orchestration above that
  swallows that into "no problem" in some call sites. Tighten so the
  caller gets a real signal.
- **METR-01/02/03 fix**: the C++ seqlock is correct; add a test that
  publishes and reads concurrently from two threads and asserts the
  snapshot is internally consistent (METR-03). The `MetricsSnapshot`
  copy inside `readMetricsSnapshot` is the entire payload and is
  sequenced by the seqlock — verify this with a multi-threaded stress
  test in `test_bridge_metrics_json.cpp` or a new
  `test_metrics_publication.cpp`.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BridgeProcessManager.terminationContinuation` — the single slot that
  must become a list.
- `BridgeEngine.publishMetricsSnapshot` /
  `BridgeEngine.readMetricsSnapshot` — the seqlock pair
  (BridgeDaemon/src/engine/BridgeEngine.cpp lines 165-188). The
  pattern is correct; what is missing is concurrent stress coverage.
- `test_bridge_process_manager.swift` — existing Swift test fixture.
- `test_bridge_metrics_json.cpp` — existing native test fixture for
  the JSON output path.

### Established Patterns
- The seqlock uses `metricsSeq_` as an odd/even lock: writers store
  `seq+1` before the write and `seq+2` after; readers loop on
  `seqBefore == seqAfter` with acquire fences. This is the standard
  double-checked-locking-for-writer pattern.
- `@MainActor` is the Swift serialisation point in
  `BridgeProcessManager`. Any new state touching termination
  continuations must stay on the main actor.
- `finishStopWithEscalation` already escalates with SIGKILL on
  timeout; the existing timeout is 5 seconds for both the graceful
  and post-kill windows.

### Integration Points
- All callers of `await waitForTermination()` /
  `finishStopWithEscalation()` in `BridgeProcessManager` must continue
  to work after the slot is replaced with a list. Call sites: `stop()`,
  `stopAsync()`, `performRestart()`, `handleHotplug()`.
- The `MetricsSnapshot` struct is consumed by `BridgeEngine`'s
  `publishMetricsSnapshot` (writer, RT thread) and read by:
  - `BridgeEngine` getters (`xrunCount`, `lastFillMs`, etc.) — control
    thread.
  - `runUntilSignal` shutdown log.
  - The `--metrics-json` stdout emitter.
  - The Swift `MetricsParser` parses the JSON line and produces a
    `BridgeMetricsSnapshot`.

### Hotspots

- `BridgeProcessManager.swift` line 42 — `terminationContinuation`
  single-slot field.
- `BridgeProcessManager.swift` line 411-420 — `waitForTermination`
  races two paths; line 604-607 — `resumeTerminationWaiters` resumes
  one continuation and nils it.
- `BridgeEngine.cpp` lines 165-188 — the seqlock itself, which
  already satisfies METR-01.

</code_context>

<specifics>
## Specific Ideas

- The new Swift "waiters" data structure should be `[CheckedContinuation<Void, Never>]`,
  guarded by the `@MainActor` isolation that already exists on the
  class. Append in `waitForTermination`, drain in
  `resumeTerminationWaiters`.
- After SIGKILL in `finishStopWithEscalation`, the second
  `waitForTermination` call must have a bounded timeout (existing code
  uses 5s). After the timeout, the helper must call
  `clearPipeHandlers()` and return `false` so the caller can react
  even if the OS never delivers the termination signal.
- The C++ seqlock stress test should spawn N reader threads and one
  writer thread, repeatedly publish snapshots with varying counter
  values, and assert that no read ever observed a torn value (where
  `underruns` or `overruns` jumped backwards, or the seqlock's
  internal fields were inconsistent with each other). A simple
  invariant: `underruns_` and `overruns_` are monotonic; the read
  snapshot's `underruns + overruns + xruns` count must be a valid
  point in time.
- The existing `--metrics-json` emitter already goes through
  `readMetricsSnapshot`, so the seqlock path is the same path the app
  UI uses. No new code needed in the emitter.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>


