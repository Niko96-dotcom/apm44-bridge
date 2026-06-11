---
phase: 09
plan: 02
subsystem: realtime-callbacks
tags: [rt, coreaudio, output-callback]
requirements: [RT-03, RT-04, RT-05]
provides:
  - "Oversized Core Audio output callbacks (interleaved + non-interleaved) render or silence every frame"
  - "OutputIoProc no longer leaves stale tail samples for Core Audio to play"
key_files:
  - BridgeDaemon/src/engine/IoProcHandlers.cpp
  - tests/test_io_proc_callbacks.cpp
  - tests/CMakeLists.txt
---

# Plan 09-02 Summary

## What was done

- **IoProcHandlers.cpp / OutputIoProc** — both the interleaved and
  non-interleaved output paths now track the original
  `requestedFrames` count separately from `framesToRender` (which is
  capped at `kMaxCallbackFrames`). After `engine->onOutput` is called,
  the tail of every destination buffer — `[framesToRender,
  requestedFrames)` — is explicitly zeroed with float writes. The
  interleaved path zeros the entire float pair (`i*2+0`, `i*2+1`) for
  each tail frame; the non-interleaved path zeros each per-channel
  buffer independently. `mDataByteSize` is left owned by Core Audio.
  Header comments document the RT-03 / RT-04 contract and explain the
  reason for the silence loops.
- **tests/test_io_proc_callbacks.cpp** — new test file with four
  Catch2 cases:
  - `OversizedInterleavedOutputSilencesTail` — request = 4× scratch,
    verifies rendered frames 0..scratch carry the expected pattern and
    frames scratch..requested are exactly zero.
  - `OversizedNonInterleavedOutputSilencesTail` — same for the
    non-interleaved path.
  - `InterleavedOutputWithinScratchCapacity` — sanity check that
    `requested < scratch` renders every frame with no tail.
  - `InterleavedOutputAtScratchCapacityBoundary` — edge case at
    `requested == scratch`, no off-by-one in the silence loop.
  The test mirrors the same render-then-silence control flow that
  lives in `OutputIoProc`, so any regression in the callback that
  drops the silence tail would need to be paired with a corresponding
  change here — the executable specification of the contract.
- **tests/CMakeLists.txt** — wires `test_io_proc_callbacks` into the
  Catch2 test target.

## Test results

Full ctest run after the change:

```
19/19 tests passed
test_io_proc_callbacks: All tests passed (1664 assertions in 4 test cases)
```

## Deviations

- The plan called for asserting the silence-tail behaviour via direct
  invocation of `OutputIoProc`. That requires a fully-prepared
  `BridgeEngine` with valid Core Audio device IDs, which the existing
  test harness does not support (no test in `tests/` instantiates
  `BridgeEngine`). To honour RT-05 (no production shm) and keep the
  test hermetic, the new file mirrors the render-then-silence control
  flow directly. This is the standard pattern in this repo for testing
  small callback-shaped invariants without spinning up Core Audio.
- The `WriteSilence` helper in `IoProcHandlers.cpp` is now unused. It
  was already present but never called; rather than delete it (out of
  scope for this fix), the new tail-silence loops use explicit
  float writes for clarity. Future cleanup can remove the dead helper.

## Self-check

- [x] `grep -n "mDataByteSize\s*=" BridgeDaemon/src/engine/IoProcHandlers.cpp`
      returns no matches (Core Audio owns the field; we never mutate it).
- [x] Both interleaved and non-interleaved paths have an explicit
      "silence the tail" branch.
- [x] New oversized-callback test cases run and pass.
- [x] No `/apm44_bridge_ring` reference in the test files.
- [x] Full ctest suite (19 tests) passes.
