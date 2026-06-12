# Phase 13: Runtime Correctness Blockers - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 13 closes runtime correctness blockers from the public-release review before release automation is trusted. It is limited to race-free metrics publication, bounded metrics JSON serialization, Core Audio callback/startup edge-case regression coverage, and cleanup of realtime helper naming or dead code that contradicts the drop-new-input policy.

</domain>

<decisions>
## Implementation Decisions

### Metrics Publication Contract
- Replace the remaining non-atomic `MetricsSnapshot` read/write contract with atomic field publication plus a sequence counter so ThreadSanitizer and standard C++ both see a race-free path.
- Keep the realtime publisher lock-free; no mutex, allocation, logging, or blocking work belongs in Core Audio IO callbacks.
- Preserve all currently exposed CLI/app fields: fill, ratio, ppm, underruns, overruns, xruns, estimated realtime latency, target fill, and SRC quality.
- Keep existing app-facing JSON field names stable so `MetricsParser` and `BridgeMetricsSnapshot` continue to decode without UI churn.

### Metrics JSON Safety
- Treat `snprintf` failure or would-have-truncated output as a fail-closed serialization result rather than reading past the fixed stack buffer.
- Add a regression test with an intentionally long `src_quality` value to prove truncation cannot overread the buffer.
- Preserve normal metrics JSON output for standard SRC quality strings.
- Avoid broad JSON infrastructure changes in this phase unless the bounded stack-buffer fix proves insufficient.

### Core Audio Edge Regression Strategy
- Add small injectable or pure test seams where needed so virtual-device output-start cleanup and mismatched non-interleaved input buffer sizing can be tested without a live Core Audio device.
- On output-start failure, cleanup must only stop/destroy IOProcs that actually exist and must avoid stopping a null or nonexistent input IOProc in virtual-device mode.
- For non-interleaved input callbacks, derive the processed frame count from the minimum available frame count across both channel buffers before clamping.
- Keep Core Audio recovery on non-realtime control paths; callbacks should remain bounded and allocation-free.

### Realtime Helper Cleanup
- Rename the overrun helper so its name matches the actual drop-new-input behavior; the current `DropOldestThenPush` wording is misleading.
- Remove the unused `WriteSilence` helper from `IoProcHandlers.cpp` unless a real call site emerges during implementation.
- Update tests and comments to make producer/consumer ownership explicit: the input producer may push and record overruns, but only the output consumer may pop.
- Keep the drop-new-input policy unchanged; this phase clarifies and verifies the shipped behavior rather than changing policy.

### the agent's Discretion
The agent may choose the smallest code shape that satisfies the phase criteria, including whether the metrics publisher keeps the existing type name or introduces a narrow internal helper type.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BridgeDaemon/src/engine/MetricsPublisher.h` already centralizes the publication API used by `BridgeEngine`.
- `BridgeDaemon/src/engine/BridgeMetrics.*` owns CLI JSON serialization through `MakeBridgeMetrics` and `ToJsonLine`.
- `tests/test_bridge_metrics_json.cpp` already covers required JSON fields, seqlock behavior, and source-level metrics snapshot guards.
- `tests/test_io_proc_callbacks.cpp` mirrors callback safety behavior for oversized output buffers and can host narrow callback regression helpers.
- `tests/test_planar_ring_buffer.cpp` and `tests/test_hardening_audit.cpp` already cover realtime overrun and source-shape invariants.

### Established Patterns
- Runtime hardening tests are primarily Catch2 tests under `tests/`, built through the existing CMake test target.
- The codebase favors small header-level helpers for realtime-safe contracts and source-level guard tests when macOS APIs are hard to exercise directly.
- Phase work should stay stack-conservative and avoid new dependencies unless they are required by the release blocker itself.

### Integration Points
- `BridgeDaemon/src/engine/BridgeEngine.cpp` publishes and reads metrics, starts/stops IOProcs, and calls the overrun helper.
- `BridgeDaemon/src/main.cpp` converts runtime metrics snapshots into CLI JSON lines.
- `App/APM44Bridge/MetricsParser.swift` and `BridgeMetricsSnapshot.swift` consume the JSON fields exposed by the daemon.
- `BridgeDaemon/src/engine/IoProcHandlers.cpp` handles interleaved and non-interleaved input/output callbacks.

</code_context>

<specifics>
## Specific Ideas

Use the accepted Phase 13 defaults from the smart-discuss gate: atomic-field metrics publication, fail-closed JSON truncation, narrow test seams for Core Audio edge cases, and realtime helper rename/dead-code cleanup.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within the Phase 13 release-blocker scope.

</deferred>
