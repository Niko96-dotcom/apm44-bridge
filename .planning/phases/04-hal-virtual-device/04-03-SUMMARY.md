---
phase: 04-hal-virtual-device
plan: 03
subsystem: driver
tags: [hal, libASPL, driver-bundle]

requires: [04-01, 04-02]
provides: [APM44Bridge.driver]
affects: [04-05]

key-files:
  created:
    - Driver/CMakeLists.txt
    - Driver/Info.plist.in
    - Driver/src/Driver.cpp
    - Driver/src/ShmIoHandler.cpp

metrics:
  duration: 35min
  completed: 2026-06-01
---

# Phase 4 Plan 03: HAL Driver Skeleton Summary

**`APM44Bridge.driver` builds: libASPL virtual output device pushing DAW audio into shm.**

## Accomplishments

- CFBundle `.driver` with plug-in factory `APM44EntryPoint`
- Device **APM44 Bridge**, UID `com.niko.apm44.bridge.device`, 44100 Hz
- `OnWriteMixedOutput` → `MmapShmRing` producer (no AirPods, no SRC)

## Deviations

- Stream format SInt16 interleaved (libASPL default path) with float conversion in handler — documented in VERIFICATION

## Self-Check: PASSED
