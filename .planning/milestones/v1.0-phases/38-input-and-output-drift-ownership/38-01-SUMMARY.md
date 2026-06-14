---
phase: 38
plan: 01
status: complete
requirements-completed: [DRIFT-01, DRIFT-02, DRIFT-03]
key_files:
  modified:
    - BridgeDaemon/src/engine/BridgeInputOverrun.h
    - BridgeDaemon/src/engine/BridgeEngine.cpp
    - BridgeDaemon/src/engine/BridgeEngine.h
    - tests/test_planar_ring_buffer.cpp
    - tests/test_hardening_audit.cpp
---

# 38-01 Summary: Remove producer-side drift mutation

## Completed

- Removed the `DriftController` dependency from `BridgeInputOverrun.h`.
- Changed `PushDroppingNewInput` to return a boolean overrun flag.
- Added `BridgeEngine::inputOverruns_` and increment it atomically from `onInput`.
- Updated producer-overrun tests to assert the returned flag and no producer-side fill mutation.

## Verification

- `cmake --build build --target test_planar_ring_buffer test_hardening_audit test_shm_io_handler`
- `ctest --test-dir build -R "test_planar_ring_buffer|test_hardening_audit|test_shm_io_handler" --output-on-failure`
- `ctest --test-dir build --output-on-failure`
