---
phase: 38
plan: 02
status: complete
requirements-completed: [DRIFT-04, DRIFT-05]
key_files:
  modified:
    - BridgeDaemon/src/engine/BridgeEngine.cpp
    - BridgeDaemon/src/engine/BridgeEngine.h
    - tests/test_hardening_audit.cpp
---

# 38-02 Summary: Publish input-overrun metrics from atomic counter

## Completed

- Metrics snapshots now publish `overruns` from `inputOverruns_`.
- Drift underrun, PI update, ratio, and ppm reads remain output-owned.
- Source-audit coverage now fails if `BridgeInputOverrun.h` reintroduces `DriftController` or `notifyOverrun`.

## Verification

- `ctest --test-dir build -R "test_planar_ring_buffer|test_hardening_audit|test_shm_io_handler" --output-on-failure`
- `ctest --test-dir build --output-on-failure`
