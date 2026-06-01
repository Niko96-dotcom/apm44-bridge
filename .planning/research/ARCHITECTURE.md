# Architecture Research

**Domain:** APM44 Bridge — virtual 44.1 kHz sink + user-space bridge to 48 kHz hardware
**Researched:** 2026-06-01
**Confidence:** HIGH

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│ DAW (44.1 kHz session)                                       │
└───────────────────────────┬─────────────────────────────────┘
                            │ Core Audio render @ 44100
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Virtual Output Device ("APM44 Bridge" or BlackHole MVP)      │
│  - 2ch Float32 non-interleaved                               │
│  - Nominal 44100 only (production)                           │
└───────────────────────────┬─────────────────────────────────┘
                            │ IOProc / shared memory (production)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Bridge Daemon (apm44-bridge) — C++ RT core                   │
│  VirtualInputCallback → RingBuffer → Resampler → DriftCtrl   │
│  → PhysicalOutputCallback @ 48000                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ AirPods Max USB-C (hardware) @ 48000                         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Menu Bar App (Swift) — non-RT                                │
│  device picker, presets, meters, start/stop                  │
└─────────────────────────────────────────────────────────────┘
```

## Major Components

### 1. HAL Audio Server Plug-in (`APM44Bridge.driver`) — production only

**Responsibilities:**
- Publish `APM44 Bridge` device to Core Audio
- Advertise `kAudioDevicePropertyAvailableNominalSampleRates` = **44100 only**
- Implement output IOProc that copies DAW buffers into shared ring (or pulls from ring for timing)
- Report latency property derived from bridge measurement

**Must NOT:**
- Open AirPods device
- Perform SRC
- Allocate in IOProc

**IPC:** Shared memory ring + lightweight signaling (Mach semaphore or atomic write index). Optional XPC for control only.

### 2. Bridge Daemon (`BridgeDaemon/`)

**Responsibilities:**
- Two `AudioDeviceIOProc` clients (or AU HAL output/input pair):
  - **Input client:** virtual device @ 44100
  - **Output client:** AirPods @ 48000
- `AudioBridge` orchestrates ring + `Resampler44To48` + `DriftController`
- `DeviceWatcher` for hotplug (non-RT thread)

**RT path:** C++ only, preallocated buffers, lock-free queue.

### 3. Menu Bar App (`App/`)

**Responsibilities:**
- Start/stop daemon or in-process engine (product decision)
- Persist `BridgeConfig`
- Display buffer fill, xrun counters, effective latency estimate
- Latency/quality presets → atomic config for engine

### 4. Shared (`Shared/`)

- `AudioFormats.h` — canonical `AudioStreamBasicDescription` helpers
- `RingBuffer.h` — SPSC float deinterleaved
- `Logging.h` — RT-safe trace ring consumed on background thread

## Data Flow (steady state)

1. DAW renders N frames @ 44100 into virtual device output buffer
2. Virtual device IOProc pushes N frames into ring (non-blocking; drop policy on overrun)
3. AirPods output IOProc requests M frames @ 48000
4. Drift controller computes `src_ratio` from ring fill vs target (e.g. 15 ms @ 44100)
5. Resampler consumes variable input frames, produces M output frames
6. Output IOProc writes to AirPods buffer

**Nominal mapping:** 147 in @ 44.1 → 160 out @ 48 per block pair; actual ratio wanders with PPM correction.

## MVP vs Production

| Aspect | MVP (BlackHole) | Production |
|--------|-----------------|------------|
| Virtual sink | BlackHole 2ch @ 44100 | `APM44Bridge.driver` |
| DAW device name | BlackHole | APM44 Bridge |
| IPC | Daemon opens BlackHole + AirPods directly | Driver ring + daemon |
| Driver signing | N/A | Developer ID + notarization |

## Suggested Build Order

1. **Console bridge** — BlackHole in → AirPods out, AVAudioConverter, no UI
2. **Drift + libsamplerate** — long-play stability
3. **Menu bar app** — presets, meters, hotplug
4. **HAL plug-in** — libASPL device @ 44100 only, ring transport
5. **Integration** — latency property, installer, QA matrix per DAW

## Reference Module Layout

```
APM44/
  Driver/APM44Bridge.driver/
  BridgeDaemon/
  App/
  Shared/
```

## Integration Points

- **Core Audio HAL** — device discovery, IOProcs
- **libASPL** — plug-in factory, device object, custom properties for latency
- **libsamplerate** — `src_process` with per-block `src_ratio`
- **SwiftUI** — `MenuBarExtra`, Settings scene
