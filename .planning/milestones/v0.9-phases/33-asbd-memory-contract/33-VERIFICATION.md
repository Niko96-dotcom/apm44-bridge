---
phase: 33-asbd-memory-contract
status: passed
score: 5/5
automated: true
completed: 2026-06-14
---

# Phase 33 Verification: ASBD Memory Contract

## Must-Haves

| Check | Status | Evidence |
|-------|--------|----------|
| Sample-rate, linear PCM, Float32, stereo, and 32-bit checks remain intact | passed | Existing checks remain in `Shared/src/AudioFormats.cpp`; targeted test suite passed |
| `mFramesPerPacket != 1` is rejected | passed | `tests/test_audio_formats.cpp` covers `mFramesPerPacket = 2` rejection |
| Interleaved stereo requires packed two-float packet/frame byte sizes | passed | Helper now checks `kAudioFormatFlagIsPacked`, `mBytesPerPacket == sizeof(float) * 2`, and `mBytesPerFrame == sizeof(float) * 2`; tests cover wrong sizes and missing packed flag |
| Non-interleaved stereo requires one-float packet/frame byte sizes | passed | Helper checks `sizeof(float)` byte sizes in the non-interleaved branch; tests cover wrong packet/frame sizes |
| Regression tests reject wrong byte-size ASBDs for both layouts | passed | `ctest --test-dir build --output-on-failure -R test_audio_formats` passed |

## Automated Checks

```bash
cmake --build build --target test_audio_formats
ctest --test-dir build --output-on-failure -R test_audio_formats
```

Result: passed.

## Human Verification

None required.
