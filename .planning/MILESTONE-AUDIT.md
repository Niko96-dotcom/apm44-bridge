# Milestone Audit: v1.0 Realtime Race Blocker Closure

**Captured:** 2026-06-14
**Source:** User-provided realtime race blocker review
**Status:** Active milestone scope anchor

## Blockers

### Blocker 1: `DriftController` touched from input and output realtime paths

`DriftController` is mutable state with ordinary non-atomic fields. The input
side can currently call `notifyOverrun()` through `PushDroppingNewInput`, while
the output side mutates and reads drift state through `update`, `notifyUnderrun`,
`smoothedRatio`, `currentPpm`, `underrunCount`, and `overrunCount`.

In BlackHole/fallback mode, input and output can plausibly run on separate Core
Audio device IOProc threads. The input callback should stop touching
`DriftController`; output should own drift control. Input overruns should be
reported through a dedicated atomic counter.

Required patch direction:
- Remove `DriftController` from `BridgeInputOverrun.h`.
- Make `PushDroppingNewInput` return whether frames were dropped.
- Add `std::atomic<uint64_t> inputOverruns_{0}` to `BridgeEngine`.
- Increment `inputOverruns_` from `BridgeEngine::onInput` with relaxed ordering.
- Publish metrics overruns from the atomic input counter while keeping underruns
  from output-owned `DriftController`.

### Blocker 2: `ShmIoHandler::ioRunning_` is a plain bool used across HAL callbacks

`OnStartIO` writes `ioRunning_ = true`, `OnStopIO` writes `ioRunning_ = false`,
and `OnProcessMixedOutput` reads the flag before pushing frames. HAL
start/stop/control callbacks and IO callbacks should not be assumed to share one
C++ execution thread.

Required patch direction:
- Make `ioRunning_` a `std::atomic<bool>`.
- Store `true` in `OnStartIO` after the ring is ready.
- Store `false` in `OnStopIO`.
- Load the flag in `OnProcessMixedOutput` before pushing frames.
- Use an explicit acquire/release or otherwise documented memory-ordering
  contract.

## High-Priority Verification

### Mono-lane queue callback serialization

The mono-lane logic now uses timestamp/logical-sample matching, searches for
compatible queued lanes, and drops older unmatched lanes instead of blindly
pairing mismatched left/right data.

The remaining risk is mutable shared lane state:
- `pendingLanes_`
- `pendingRead_`
- `pendingWrite_`
- `pendingCount_`
- `pendingInterleaved_`

This is acceptable only if libASPL/Core Audio serializes `OnProcessMixedOutput`
for the mono-lane streams. Before release, the milestone must add one of:
- A source comment citing the libASPL callback serialization contract.
- A test/fake handler that exercises the expected serialized mono-lane call
  pattern.
- A redesign that avoids shared mutable lane assembly unless serialization is
  proven.

## Required Regression Tests

- `BridgeInputOverrunDoesNotIncludeDriftController`
- `BridgeInputOverrunReturnsOverrunFlagInsteadOfMutatingDrift`
- `BridgeEngineInputOverrunCounterIsAtomic`
- `ShmIoHandlerIoRunningIsAtomic`
- `ShmIoHandlerMonoLaneCallbackSerializationDocumented`

## Final Patch Order

1. Remove `DriftController` mutation from the input callback path.
2. Add an atomic input-overrun counter in `BridgeEngine`.
3. Make `ShmIoHandler::ioRunning_` atomic.
4. Prove or document libASPL serializes mono-lane `OnProcessMixedOutput` calls.
5. Run full macOS release validation and DAW/hardware soak.

