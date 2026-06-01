---
phase: 01-blackhole-console-bridge
reviewed: 2026-06-01T12:00:00Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - BridgeDaemon/src/main.cpp
  - BridgeDaemon/src/CliOptions.h
  - BridgeDaemon/src/CliOptions.cpp
  - BridgeDaemon/src/engine/BridgeEngine.h
  - BridgeDaemon/src/engine/BridgeEngine.cpp
  - BridgeDaemon/src/engine/IoProcHandlers.h
  - BridgeDaemon/src/engine/IoProcHandlers.cpp
  - BridgeDaemon/src/engine/AudioConverterSrc.h
  - BridgeDaemon/src/engine/AudioConverterSrc.cpp
  - BridgeDaemon/src/hal/DeviceEnumerator.h
  - BridgeDaemon/src/hal/DeviceEnumerator.cpp
  - BridgeDaemon/src/hal/FormatNegotiator.h
  - BridgeDaemon/src/hal/FormatNegotiator.cpp
  - BridgeDaemon/src/hal/HalTypes.h
  - Shared/include/apm44/PlanarRingBuffer.h
  - Shared/src/PlanarRingBuffer.cpp
  - Shared/include/apm44/AudioFormats.h
  - Shared/src/AudioFormats.cpp
  - Shared/include/apm44/RtConstraints.h
  - tests/test_audio_formats.cpp
  - tests/test_device_enumerator.cpp
  - tests/test_planar_ring_buffer.cpp
  - tests/test_audio_converter_src.cpp
findings:
  critical: 4
  warning: 4
  info: 2
  total: 10
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-06-01  
**Depth:** standard  
**Files Reviewed:** 20  
**Status:** issues_found (4 critical addressed in-tree during review)

## Summary

Phase 1 delivers a coherent HAL bridge skeleton: device enumeration, format negotiation, persistent `AudioConverter`, lock-free planar ring, and dual IOProcs. Unit tests cover ring capacity, ASBD helpers, device matching, and SRC ratio smoke test.

Four **BLOCKER**-class issues were found in the real-time path and rate bookkeeping. All four were fixed during this review (`BridgeEngine.cpp`, `BridgeEngine.h`, `AudioConverterSrc.cpp`). Build and all four Catch2 tests pass after fixes.

Remaining items are **WARNING**/**INFO** (IOProc validation, buffer-size assumptions, test gaps). No security issues identified in scoped code.

## Critical Issues

### CR-01: Shared scratch buffers between input and output IOProcs (data race)

**File:** `BridgeDaemon/src/engine/BridgeEngine.cpp:56-93` (pre-fix)  
**Issue:** `onInput` and `onOutput` both used `channel0Scratch_` / `channel1Scratch_`. Input and output IOProcs can run concurrently on different threads, causing torn reads/writes and corrupted audio.  
**Fix:** Dedicated `inputDropScratch0_/1_` for the input drop path and `outputScratch0_/1_` for output pop/SRC.  
**Status:** Fixed in review.

### CR-02: Possible `std::vector::resize` on the RT path

**File:** `BridgeDaemon/src/engine/AudioConverterSrc.cpp:109-111` (pre-fix)  
**Issue:** `AudioConverterSrc::convert()` could resize `outputInterleaved_` inside the output IOProc, violating Phase 1 RT rules (no malloc in callbacks).  
**Fix:** Return `false` if preallocated buffer is too small; sizing remains in `prepare()` only.  
**Status:** Fixed in review.

### CR-03: Wrong ring pop size (44.1 kHz vs 48 kHz frame count)

**File:** `BridgeDaemon/src/engine/BridgeEngine.cpp:72-74` (pre-fix)  
**Issue:** `onOutput` popped `min(frames, scratch)` where `frames` is the **output** buffer size at 48 kHz. The ring stores **44.1 kHz** frames. Popping one output frame’s worth of 44.1 kHz samples per 48 kHz output callback drains the ring ~9% faster than fill → chronic underruns/xruns.  
**Fix:** Pop `ceil(outputFrames * 44100 / 48000)` frames via `InputFramesForOutputFrames()`.  
**Status:** Fixed in review.

### CR-04: Ring overflow handler re-pushed already-written samples

**File:** `BridgeDaemon/src/engine/BridgeEngine.cpp:56-65` (pre-fix)  
**Issue:** On partial `push`, code dropped oldest frames then called `push(channels, frames)` from the start, duplicating samples already written.  
**Fix:** After drop, `push` only `channels[i] + pushed` for `frames - pushed` remainder.  
**Status:** Fixed in review.

## Warnings

### WR-01: IOProc assumes equal `mDataByteSize` on both channels

**File:** `BridgeDaemon/src/engine/IoProcHandlers.cpp:40,62`  
**Issue:** Frame count is taken from buffer 0 only; mismatched channel buffer sizes would mis-size processing.  
**Fix:** Require `mNumberBuffers >= 2` and equal `mDataByteSize` on both buffers; otherwise write silence / return early.

### WR-02: Silent no-op when buffer pointers are null

**File:** `BridgeDaemon/src/engine/IoProcHandlers.cpp:37-38,59-60`  
**Issue:** Null `mData` returns `noErr` without counting an xrun; can hide HAL misconfiguration.  
**Fix:** Increment `xruns_` from a lock-free counter or document as intentional; at minimum log once on main thread at start if format probe fails.

### WR-03: `findByUid` / `resolve*` call `listAll()` repeatedly

**File:** `BridgeDaemon/src/hal/DeviceEnumerator.cpp:149-179`  
**Issue:** `preflight` + `main` each enumerate all devices multiple times (allocations on main thread only — not RT, but slow and allocates).  
**Fix:** Cache device list per `DeviceEnumerator` instance or pass resolved `BridgeDevicePair` through a single enumeration.

### WR-04: Scratch size fixed at 1024 without tying to negotiated buffer size

**File:** `BridgeDaemon/src/engine/BridgeEngine.cpp:49-53`  
**Issue:** If HAL delivers >1024 frames per callback, `maxPop` caps below need and SRC may underrun output. Phase 1 targets 512; risk if user device ignores buffer-size set.  
**Fix:** Size scratch from `max(ReadBufferFrameSize(input), ReadBufferFrameSize(output))` after negotiation, with a documented ceiling.

## Info

### IN-01: Unused `convertOut0_` / `convertOut1_` members removed

**File:** `BridgeDaemon/src/engine/BridgeEngine.h` (pre-fix)  
**Issue:** Vectors were resized in `prepare()` but never referenced (dead allocation).  
**Fix:** Removed during CR-01 refactor.

### IN-02: No automated test for ring drop policy or rate-scaled pop

**File:** `tests/test_planar_ring_buffer.cpp`  
**Issue:** Ring push/pop and capacity are tested; bridge-level overflow and `InputFramesForOutputFrames` are not.  
**Fix:** Add unit tests for `InputFramesForOutputFrames` (extract to Shared or test helper) and integrated drop policy with a mock ring.

---

_Reviewed: 2026-06-01_  
_Reviewer: Claude (gsd-code-reviewer)_  
_Depth: standard_
