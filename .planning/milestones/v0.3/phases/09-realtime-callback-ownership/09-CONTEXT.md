# Phase 9: Realtime Callback Ownership - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous)

<domain>
## Phase Boundary

Realtime audio callbacks obey their ownership contracts: the input producer
path never consumes from the ring, oversized output callbacks render or
silence every actual frame, and the selected overrun policy is documented in
code and exercised by tests. Deliverables: fix `BridgeInputOverrun.h` so the
producer no longer calls `PlanarRingBuffer::pop()`, make `VirtualDeviceFeed`
output paths safe against oversized callbacks, and add Catch2 tests that
cover both behaviors using a non-production shared-memory name.
</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices for the overrun policy, output-scratch sizing, and
test scaffolding are at Claude's discretion. Constraints from REQUIREMENTS.md
(RT-01..RT-05) are authoritative:

- The input producer path must not call `ring.pop()`.
- The chosen overrun behavior must be explicit, tested, and either drop new
  input or perform oldest-frame trimming only from the output consumer side.
- Output callbacks larger than the scratch capacity must render or explicitly
  silence every actual frame (interleaved and non-interleaved).
- Tests must not touch `/apm44_bridge_ring` (use isolated shm names).

The natural fit is to keep the policy "drop new input" on the producer side
(current `push` already returns how many frames were accepted; surface that
and `drift.notifyOverrun()` when the input is too full) and only have the
output consumer trim oldest frames when its scratch is too small. Both the
interleaved and non-interleaved output callbacks will write their full actual
frame count (silencing any tail beyond capacity) so `ioData` never carries
stale samples.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `apm44::PlanarRingBuffer` (Shared/include/apm44/PlanarRingBuffer.h) — SPSC
  lock-free planar float ring; `push` returns the number of frames actually
  accepted.
- `apm44::DriftController::notifyOverrun()` — already wired into the overrun
  path; can be called when the input push is short or rejected.
- `tests/test_planar_ring_buffer.cpp` — existing Catch2 fixture using a
  local `PlanarRingBuffer` instance (no shared memory).

### Established Patterns
- Catch2 tests live under `tests/` with a `test_*.cpp` naming convention and
  are wired into the existing CMake test target (see
  `test_mmap_shm_ring.cpp`, `test_shm_object_identity.cpp`).
- Bridge code uses C++17 in the `apm44` namespace; producer/consumer split
  is enforced by the `push`/`pop` API and `DriftController` side effects.
- The producer-side overrun helper currently lives in
  `BridgeDaemon/src/engine/BridgeInputOverrun.h` and is included from
  `BridgeEngine.cpp`.

### Integration Points
- `BridgeEngine.cpp` calls `DropOldestThenPush` from the input path.
- `VirtualDeviceFeed.cpp` runs the output callbacks (interleaved +
  non-interleaved) and is the place that must size for oversized Core Audio
  invocations.
- `Shared/src/PlanarRingBuffer.cpp` exposes `push`/`pop` — no API change
  needed if we only fix the call sites and improve `push` return-value use.

### Current Bug Hotspot
`BridgeInputOverrun::DropOldestThenPush` (the entire file, lines 9–25)
violates RT-01: it calls `ring.pop()` from the producer path to drop oldest
frames, which crosses the SPSC ownership line. The fix is to remove the
`pop` call and instead rely on `push`'s accepted-frame count, surfacing the
overrun to `DriftController` when frames are dropped or rejected.

</code_context>

<specifics>
## Specific Ideas

- Use `push` return value to detect "not all frames accepted" and call
  `drift.notifyOverrun()` in that case — gives the same metric signal without
  touching consumer state.
- For oversized output callbacks, the established approach in this codebase
  is "write what we have, zero the rest" in the interleaved path; mirror
  that in the non-interleaved path so both callbacks are safe against
  `ioData->mNumberFrames > scratchCapacity`.
- Add a Catch2 test that exercises `PlanarRingBuffer` directly under the new
  policy (push against a full ring → no frames accepted, `notifyOverrun`
  called, no `pop` on producer side).
- Add a Catch2 test that drives `VirtualDeviceFeed` (or a stripped output
  helper) with a callback frame count larger than scratch and asserts every
  frame in `ioData` was either rendered or zeroed, with no garbage tail.
- Tests must construct their own `PlanarRingBuffer` and not touch
  `/apm44_bridge_ring` (RT-05).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>
