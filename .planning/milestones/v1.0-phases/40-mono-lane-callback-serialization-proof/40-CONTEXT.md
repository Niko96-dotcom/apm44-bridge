# Phase 40: Mono-Lane Callback Serialization Proof - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 40 proves that mono-lane assembly state is used under the expected serialized HAL/libASPL IO callback contract, and guards that proof with tests and source-audit coverage.

</domain>

<decisions>
## Implementation Decisions

### Serialization Contract
- Cite libASPL's `Device` contract: IO handler operations are invoked on the realtime thread and serialized.
- Do not add locks around mono-lane pending queues, because that would harm the realtime path and duplicate libASPL's IO serialization.
- Keep timestamp/logical-sample mismatch handling fail-closed.

### Regression Coverage
- Add a named serialized left/right mono-lane test.
- Add source-audit guards requiring the serialization citation when pending mono-lane state exists.
- Keep mismatch/drop coverage passing.

### the agent's Discretion
Prefer proof plus guards over redesign unless tests reveal unsafe behavior.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Driver/src/ShmIoHandler.cpp` already queues mono lanes and flushes pairs with timestamp checks.
- `third_party/libASPL/include/aspl/Device.hpp` documents serialized IO handler invocation.
- `third_party/libASPL/src/Device.cpp` wraps IO operations in `ioMutex_`.
- `tests/test_shm_io_handler.cpp` already covers mono lane pairing, rollover, mismatch rejection, repeated lanes, and missing stream lanes.

### Established Patterns
- HAL driver tests use Catch2 and a unique shm ring name per test.
- Source-audit tests enforce architectural contracts that are hard to exercise dynamically.

### Integration Points
- `PendingLaneBlock`, `pendingLanes_`, and `flushPendingLanes` are the mono-lane shared state under review.

</code_context>

<specifics>
## Specific Ideas

Make the contract visible next to the pending-lane state so future maintainers see why no callback-local lock exists there.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
