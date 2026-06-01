# Phase 1 Research: BlackHole Console Bridge

**Researched:** 2026-06-01  
**Confidence:** HIGH (Apple HAL + AudioToolbox patterns); MEDIUM (device UID heuristics on user hardware)

## Summary

Phase 1 delivers a **greenfield** C++20 user-space daemon (`apm44-bridge`) that bridges **BlackHole 2ch @ 44.1 kHz** to **AirPods Max USB-C @ 48 kHz** using **persistent AudioToolbox `AudioConverter`**, raw HAL IOProcs, and a fixed-capacity planar ring buffer. No custom HAL driver, Swift UI, libsamplerate drift engine, or LaunchAgent in this phase.

## Standard Stack (Phase 1)

| Component | Choice | Notes |
|-----------|--------|-------|
| Language | C++20 | `BridgeDaemon/`, `Shared/` only |
| Build | CMake 3.28+ | `cmake -G Xcode` or Ninja; agent-friendly |
| I/O | `AudioDeviceCreateIOProcID` + `AudioDeviceStart` | TN2223; not AU HALOutput |
| SRC | `AudioConverter` (AudioToolbox C API) | One instance at startup; never per-buffer `AudioConverterNew` |
| Formats | Float32, 2ch, non-interleaved | Negotiate via `AudioStreamBasicDescription` before start |
| Logging | stderr or spdlog on main thread only | Never in IOProc |
| BlackHole | External v0.6.1+ | GPL — document install; fail fast if missing |

## Architecture (Phase 1 subset)

```
DAW @ 44100 → BlackHole 2ch (input IOProc @ 44100)
                    ↓ planar ring (preallocated)
              AudioConverter 44100→48000
                    ↓
         AirPods USB-C (output IOProc @ 48000)
```

**Not in Phase 1:** drift controller, variable `src_ratio`, XPC, shm driver ring, hotplug watcher.

## Device discovery heuristics

| Endpoint | Selection rule |
|----------|----------------|
| Input default | Device name contains `BlackHole` and channel count ≥ 2; prefer `BlackHole 2ch` |
| Output default | Device name matches `AirPods Max` + transport hint `USB` / `USB-C` when available |
| Override | `--input-device UID` / `--output-device UID` |

**Nominal rates:** Verify input stream reports **44100 Hz** and output **48000 Hz** via `kAudioDevicePropertyNominalSampleRate` / stream format — do **not** attempt to set AirPods to 44100 (PITFALLS #3).

## AudioConverter streaming pattern

1. Create converter once with input/output `AudioStreamBasicDescription` (44100/48000, float32, 2ch, non-interleaved).
2. Prime with silence until first valid input frame arrives.
3. Per output callback: pull from ring → `AudioConverterFillComplexBuffer` → write output buffer.
4. On conversion failure in RT path: emit silence for that buffer; increment xrun counter on background thread only.

**Nominal frame ratio:** 147 input frames → 160 output frames per block pair at nominal rates (document actual buffer sizes from hardware).

## Real-time constraints (ENG-05)

| Allowed in IOProc | Forbidden in IOProc |
|-------------------|---------------------|
| Read/write preallocated buffers | `malloc` / `free` |
| Lock-free ring push/pop | mutexes |
| `AudioConverterFillComplexBuffer` on persistent instance | `NSLog`, spdlog, file I/O |
| Atomic counter bumps (relaxed) | device enumeration |

All HAL property queries and converter creation occur **before** `AudioDeviceStart`.

## Build layout (recommended)

```
CMakeLists.txt
BridgeDaemon/
  CMakeLists.txt
  src/main.cpp
  src/CliOptions.{h,cpp}
  src/hal/{DeviceEnumerator,FormatNegotiator}.{h,cpp}
  src/engine/{BridgeEngine,AudioConverterSrc,IoProcHandlers}.{h,cpp}
Shared/
  include/apm44/{AudioFormats,PlanarRingBuffer,RtConstraints}.h
  src/AudioFormats.cpp
docs/mvp-routing.md
scripts/verify-devices.sh
tests/  (Catch2 or GoogleTest via CMake)
```

## Verification strategy

| Check | Method |
|-------|--------|
| Devices present | `scripts/verify-devices.sh` (system_profiler + optional SwitchAudioSource) |
| Build | `cmake --build build` |
| Unit | ring buffer + format helpers tests |
| E2E | Human: DAW 440 Hz → BlackHole → `apm44-bridge` → AirPods audible tone |

## Out of scope (this phase)

- libsamplerate / drift (Phase 2)
- Menu bar / XPC (Phase 3)
- `APM44Bridge.driver` (Phase 4)
- LaunchAgent auto-start
- Hotplug recovery
- Developer ID signing

## Sources

| Source | Used for |
|--------|----------|
| `.planning/research/STACK.md` | HAL IOProc, AudioConverter, CMake |
| `.planning/research/ARCHITECTURE.md` | Module layout, MVP vs production |
| `.planning/research/PITFALLS.md` | RT safety, AirPods rate, GPL |
| Apple TN2223 | `AudioDeviceCreateIOProcID` |
| Apple TN3136 | Persistent converter streaming |
| `01-CONTEXT.md` | Locked decisions D-01..D-05 equivalent |

## Architectural Responsibility Map

| Tier | Components |
|------|------------|
| Non-RT setup | CLI, device enum, format negotiation, converter create, buffer prealloc, logging |
| RT callbacks | IOProc in/out, ring, AudioConverter fill, silence on failure |
| Post-RT | xrun stats print on main thread, signal handling |
