# Phase 38: Input and Output Drift Ownership - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 38 removes producer-side drift mutation from input callback overrun handling. Input callbacks may push audio and atomically count dropped input frames; output callbacks remain the exclusive owner of `DriftController` PI updates, underrun notification, and drift metrics reads.

</domain>

<decisions>
## Implementation Decisions

### Realtime Ownership
- `BridgeInputOverrun.h` must not include, name, or call `DriftController`.
- `PushDroppingNewInput` should return whether the ring accepted fewer frames than requested.
- `BridgeEngine::onInput` owns the input-overrun counter increment through a relaxed atomic fetch-add.
- Metrics publication combines output-owned drift underruns with the input-overrun atomic.

### Regression Coverage
- Preserve the existing drop-new-input ring behavior and update tests to assert the returned overrun flag.
- Add source-audit guards that fail if `DriftController` or `notifyOverrun` returns to `BridgeInputOverrun.h`.

### the agent's Discretion
Implementation choices should follow existing realtime constraints and avoid locks or allocation on callback paths.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BridgeDaemon/src/engine/BridgeInputOverrun.h` currently wraps producer overrun policy.
- `BridgeDaemon/src/engine/BridgeEngine.cpp` owns input and output callbacks plus metrics publication.
- `tests/test_planar_ring_buffer.cpp` and `tests/test_hardening_audit.cpp` already cover the drop-new-input policy.

### Established Patterns
- Callback counters use `std::atomic<uint64_t>` with relaxed ordering where no synchronization is required.
- Source-audit tests read repository files directly and assert forbidden strings are absent.

### Integration Points
- `BridgeEngine::publishMetricsSnapshot` is the single bridge from callback state into `MetricsPublisher`.

</code_context>

<specifics>
## Specific Ideas

Keep the phase focused on ownership and metrics truth; do not redesign `DriftController` or ring buffering.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
