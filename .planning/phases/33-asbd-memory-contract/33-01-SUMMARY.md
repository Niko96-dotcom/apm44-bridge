---
phase: 33-asbd-memory-contract
plan: 01
subsystem: audio-format-validation
tags: [core-audio, asbd, hal]
key-files:
  created:
    - .planning/phases/33-asbd-memory-contract/33-01-SUMMARY.md
  modified:
    - Shared/src/AudioFormats.cpp
requirements-completed: [ASBD-01, ASBD-02, ASBD-03]
completed: 2026-06-14
---

# Phase 33 Plan 01 Summary: ASBD Layout Contract

## Accomplishments

- Added `mFramesPerPacket == 1` as a required part of the accepted Float32 stereo ASBD contract.
- Required packed two-float packet/frame byte sizes for interleaved Float32 stereo.
- Required one-float packet/frame byte sizes for non-interleaved Float32 stereo.

## Verification

```bash
cmake --build build --target test_audio_formats
ctest --test-dir build --output-on-failure -R test_audio_formats
```

Result: passed.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED
