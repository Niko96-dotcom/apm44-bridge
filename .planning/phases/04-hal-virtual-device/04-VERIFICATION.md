# Phase 4 Verification: HAL Virtual Device

**Verified:** 2026-06-01  
**Verdict:** **PARTIAL** — software path complete; HAL load + DAW matrix require manual QA

## Success criteria (ROADMAP)

| # | Criterion | Status | Evidence |
|---|-----------|--------|------------|
| 1 | User can select **APM44 Bridge** @ 44100 in AMS/DAW without BlackHole | **MANUAL** | Driver builds; unsigned load not verified in CI |
| 2 | UID `com.niko.apm44.bridge.device`, 44100-only nominal | **PARTIAL** | UID set in `Driver/src/Driver.cpp`; 44100-only rate list not hardened |
| 3 | Driver does not open AirPods / no SRC in driver | **PASS** | `ShmIoHandler` only pushes shm; no HAL output to AirPods |
| 4 | Documented shm IPC ring transport | **PASS** | `Shared/include/apm44/ShmRingLayout.h`, `docs/hal-driver.md` |
| 5 | DAW @ 44100 → APM44 Bridge (Logic/Ableton) | **MANUAL** | Not run in this session |

## Requirements

| ID | Status | Notes |
|----|--------|-------|
| DEV-01 | PARTIAL | Device skeleton; host enumeration needs signed install |
| DEV-02 | PASS | 2ch SInt16 packed in driver stream (DAW path); daemon uses float32 |
| DEV-03 | MANUAL | `--virtual-device` ready; DAW routing unchecked |
| DRV-01 | PASS | `APM44Bridge.driver` builds with libASPL v3.1.2 |
| DRV-02 | PARTIAL | 44100 sample rate set; exclusive nominal list TBD |
| DRV-03 | PASS | `MmapShmRing` + tests; driver producer + daemon consumer |

## Automated checks

| Check | Result |
|-------|--------|
| `cmake --build build --target APM44Bridge apm44-bridge` | PASS |
| `ctest --test-dir build` (11 tests) | PASS |
| `test_mmap_shm_ring` | PASS |
| `test_virtual_device_feed` | PASS |
| `scripts/verify-hal-driver.sh` | PASS (structural); WARN unsigned / not loaded |

## Known gaps (intentional Phase 4 skeleton)

1. **Developer ID signing** — Phase 5; macOS 15+ may refuse ad-hoc HAL plug-in
2. **Menu bar app** — still spawns BlackHole path; does not pass `--virtual-device`
3. **Nominal rates property** — only `DeviceParameters.SampleRate = 44100`; restrict `GetAvailableNominalSampleRates` later
4. **Driver stream format** — SInt16 interleaved in HAL; acceptable for MVP handoff; float32 non-interleaved is a future hardening item
5. **End-to-end audio** — requires: install driver → reload coreaudiod → DAW play → `apm44-bridge --virtual-device`

## Manual test procedure

1. Build and install: `./scripts/install-driver.sh` + kickstart coreaudiod
2. Confirm **APM44 Bridge** in Audio MIDI Setup @ 44100 Hz
3. DAW output → APM44 Bridge, 44.1 kHz session
4. `build/BridgeDaemon/apm44-bridge --virtual-device --list-devices` then run with AirPods UID
5. Expect audio on AirPods; watch daemon underrun/xrun counters

## Self-check

- [x] `build/Driver/APM44Bridge.driver` exists
- [x] Shm layout header documented
- [x] `--virtual-device` in `--help`
