---
status: completed
completed: "2026-06-02"
quick_id: 260602-wtj
slug: fix-hal-virtual-device-production-contra
---

# Quick Task 260602-wtj Summary

## Outcome

Fixed the HAL virtual-device production contract mismatch. The APM44 Bridge driver no
longer exposes or converts SInt16 packed stereo on the driver-to-daemon path.

## Changes

- Added driver format helpers for the APM44 production contract: logical 2-channel
  Float32 non-interleaved 44100 Hz only, represented to HAL as two Float32 mono
  output lanes with starting channels 1 and 2.
- Updated `Driver.cpp` to create two output streams instead of one packed stereo
  SInt16 stream.
- Updated `ShmIoHandler` to consume libASPL `ProcessMix` Float32 callbacks, pass
  through canonical interleaved stereo when provided, and assemble left/right mono
  lanes into the existing interleaved Float32 shm ring with fixed-size storage.
- Removed SInt16 scaling from the shm push path.
- Added focused tests for the driver format contract and shm push behavior. Test
  rings use unique names and do not unlink `/apm44_bridge_ring`.

## RT Safety

The changed audio callback path adds no malloc, locks, logging, Swift/Obj-C,
file I/O, or device enumeration. The lane assembly uses fixed storage allocated
with the handler object and the existing `MmapShmRing::pushInterleaved` RT path.

## Verification

- `cmake --build build`: passed.
- `git diff --check`: passed.
- `ctest --test-dir build --output-on-failure`: 13/13 passed.
- `./scripts/ci.sh`: passed, including native tests and Swift app tests.
- Installed the matching built driver because the installed HAL executable hash
  differed after the final rebuild.
- `./scripts/verify-hal-driver.sh`: structural checks passed. Expected local dev
  warnings remain for Gatekeeper, Developer ID signing, and Hardened Runtime.
- `build/BridgeDaemon/apm44-bridge --shm-status`: `shm_status=ok`,
  `sample_rate=44100`, `channels=2`.
- Live Core Audio probe after install:
  - output stream count: 2.
  - stream starting channels: 1 and 2.
  - physical stream format: Float32, non-interleaved flag set, 44100 Hz, 1ch.
  - stream configuration: 2 buffers, 1 channel each.
  - IOProc output shape: 2 buffers, 1 channel each.

Note: Core Audio reports each mono virtual ASBD as packed Float32 (`flags=0x9`),
which is layout-equivalent for a one-channel stream. The DAW-facing device buffer
shape is still non-interleaved stereo: two one-channel output buffers.
