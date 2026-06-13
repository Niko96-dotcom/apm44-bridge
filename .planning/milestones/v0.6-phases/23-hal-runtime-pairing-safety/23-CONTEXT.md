# Phase 23: HAL Runtime Pairing Safety - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 23 closes HAL shared-memory runtime safety issues before release closure: mono lane timestamp pairing must be explicit and fail closed, stopped IO callbacks must not process or write frames, and HAL shared-memory drop-policy comments must describe the bounded ring behavior accurately.

</domain>

<decisions>
## Implementation Decisions

### Mono Lane Pairing Contract
- Pair mono lanes only when their logical HAL sample time matches within a narrow tolerance.
- Compute logical sample time from `zeroTimestamp + timestamp` so period rollover is handled intentionally rather than by accidental raw timestamp matching.
- Use a named predicate for lane pairing so future changes cannot silently reintroduce arbitrary mismatch pairing.
- Drop stale unmatched lane heads while looking for a valid match, but never push a left/right pair that the predicate rejects.

### Stopped IO Guard
- Treat `OnStopIO()` as authoritative for mixed-output callbacks.
- Return before stream processing and before shared-memory writes when IO is stopped.
- Keep start/stop behavior allocation-free and suitable for callback-adjacent paths.
- Cover stopped-IO rejection with a Catch2 regression that proves no shm frames are written after stop.

### Drop Policy Documentation
- Update the HAL shm push comment to match `MmapShmRing::pushInterleaved`: bounded ring writes only available capacity and drops incoming tail frames when full.
- Do not change the ring policy in this phase.
- Keep producer/consumer ownership unchanged.
- Prefer a concise comment over broad documentation churn.

### the agent's Discretion
The agent may choose the smallest helper shape that makes timestamp pairing readable and testable, provided the public HAL behavior and existing successful pairing cases remain intact.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Driver/src/ShmIoHandler.cpp` owns `OnProcessMixedOutput`, mono-lane queuing, lane matching, and shm pushes.
- `Driver/src/ShmIoHandler.h` owns the pending lane block shape and private helper declarations.
- `tests/test_shm_io_handler.cpp` already exercises stereo push, same-timestamp mono pairing, rollover pairing, repeated-lane queueing, and null-stream mono rejection.
- `Shared/src/MmapShmRing.cpp` shows the actual bounded push behavior: it writes up to `availableToWrite()` and returns the accepted frame count.

### Established Patterns
- HAL behavior is covered with targeted Catch2 tests that create an isolated shm ring name per test.
- Tests build `Apm44OutputStream` instances directly rather than depending on live Core Audio devices.
- Phase runtime fixes should avoid mutexes, allocation, logging, or broad architectural changes in callback paths.

### Integration Points
- `OnProcessMixedOutput` receives both `zeroTimestamp` and `timestamp` from libASPL.
- `pushMonoLane` currently stores only raw `timestamp`, which is insufficient to document rollover behavior.
- `flushPendingLanes` currently falls through to `pushLanePair` even when no matching timestamp is found.

</code_context>

<specifics>
## Specific Ideas

Use `zeroTimestamp + timestamp` as the logical lane time, keep the rollover tolerance named and bounded at 128 frames, and add regressions for normal matching, rollover matching, unrelated mismatch rejection, and stopped-IO rejection.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within Phase 23 scope.

</deferred>
