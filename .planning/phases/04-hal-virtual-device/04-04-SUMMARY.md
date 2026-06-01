---
phase: 04-hal-virtual-device
plan: 04
subsystem: daemon
tags: [virtual-device, cli]

requires: [04-02]
provides: [--virtual-device]
affects: [04-05]

key-files:
  created:
    - BridgeDaemon/src/engine/VirtualDeviceFeed.cpp
    - tests/test_virtual_device_feed.cpp
  modified:
    - BridgeDaemon/src/engine/BridgeEngine.cpp
    - BridgeDaemon/src/CliOptions.cpp
    - BridgeDaemon/src/hal/FormatNegotiator.cpp

metrics:
  duration: 30min
  completed: 2026-06-01
---

# Phase 4 Plan 04: Daemon Virtual Device Mode Summary

**`apm44-bridge --virtual-device` consumes shm in the output IOProc path (no BlackHole input client).**

## Accomplishments

- `VirtualDeviceFeed` drains shm → internal `PlanarRingBuffer`
- Output-only IOProc when virtual mode enabled
- `negotiateVirtualOutput()` for AirPods-only HAL negotiation
- `test_virtual_device_feed` passes

## Deviations

None.

## Self-Check: PASSED
