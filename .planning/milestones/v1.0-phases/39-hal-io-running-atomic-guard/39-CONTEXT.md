# Phase 39: HAL IO Running Atomic Guard - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 39 makes `ShmIoHandler::ioRunning_` race-free across HAL start/stop/control callbacks and mixed-output callbacks while preserving stopped-IO behavior.

</domain>

<decisions>
## Implementation Decisions

### Atomic Guard
- Store `true` after ring readiness with release ordering in `OnStartIO`.
- Store `false` with release ordering in `OnStopIO`.
- Load with acquire ordering at the top of `OnProcessMixedOutput` before processing or writing frames.
- Keep stopped-IO behavior unchanged: mixed output after stop returns without stream processing or shm writes.

### Regression Coverage
- Add source-audit guards for `<atomic>`, `std::atomic<bool>`, and explicit memory-order use.
- Keep existing behavior tests for stopped IO.

### the agent's Discretion
Use the smallest code change that removes the data race; do not add locks to realtime callbacks.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Driver/src/ShmIoHandler.h` owns the `ioRunning_` member.
- `Driver/src/ShmIoHandler.cpp` handles `OnStartIO`, `OnStopIO`, and `OnProcessMixedOutput`.
- `tests/test_shm_io_handler.cpp` already checks ignored mixed output after stop.

### Established Patterns
- Realtime gates should be cheap and non-blocking.
- Source-audit tests are acceptable for structural callback contracts.

### Integration Points
- `OnProcessMixedOutput` is the only mixed-output path that should observe the guard before stream processing.

</code_context>

<specifics>
## Specific Ideas

Use acquire/release ordering to document cross-callback visibility without overstating a stronger synchronization contract than this flag requires.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
