---
status: in_progress
created: "2026-06-02"
quick_id: 260602-wtj
slug: fix-hal-virtual-device-production-contra
---

# Quick Task 260602-wtj: HAL Virtual Device Production Contract

Fix the remaining APM44 Bridge HAL virtual-device contract mismatch so the DAW-facing device exposes only 2ch Float32 non-interleaved 44100 Hz and the driver pushes Float32 stereo into the shared-memory ring without SInt16 scaling.

## Must Haves

- The production `.driver` stream format is 44100 Hz only, 2 channels, Float32, non-interleaved.
- `ShmIoHandler` forwards stereo Float32 frames from HAL buffers into shm without SInt16 conversion.
- Tests prove both the driver format contract and shm push behavior.
- RT callback path remains free of malloc, locks, logging, Swift/Obj-C, file I/O, and device enumeration.
- Verification covers cmake build, ctest, available CI/HAL scripts, and `apm44-bridge --shm-status` after any needed install/reload.
- Tests must not unlink `/apm44_bridge_ring`.

## Tasks

1. Inspect libASPL stream and IO buffer behavior before changing driver code.
   - Files: `third_party/libASPL/include/aspl/Stream.hpp`, `third_party/libASPL/src/Stream.cpp`, `third_party/libASPL/src/Device.cpp`, `Driver/src/Driver.cpp`, `Driver/src/ShmIoHandler.cpp`
   - Verify: document how libASPL represents physical/virtual stream formats and what buffer layout `DoIOOperation` receives.

2. Implement Float32 non-interleaved driver/shm contract.
   - Files: `Driver/src/Driver.cpp`, `Driver/src/ShmIoHandler.{h,cpp}`, shared test helpers if needed.
   - Verify: no RT-prohibited operations are added to IO callbacks.

3. Add targeted tests and run requested verification.
   - Files: `tests/`, `scripts/` only if test support needs a narrow adjustment.
   - Verify: `cmake --build`, `ctest`, `scripts/ci.sh` if available, `scripts/verify-hal-driver.sh`, and live `--shm-status` if install/reload is needed.
