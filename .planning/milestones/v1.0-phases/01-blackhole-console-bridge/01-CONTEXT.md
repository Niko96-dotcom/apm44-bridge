# Phase 1: BlackHole Console Bridge - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning
**Mode:** Smart discuss (yolo — recommended answers accepted)

<domain>
## Phase Boundary

Deliver a user-space bridge daemon that reads BlackHole 2ch @ 44.1 kHz, resamples to 48 kHz with AVAudioConverter/AudioToolbox, and plays to AirPods Max USB-C @ 48 kHz. Include documented manual routing (DAW → BlackHole → bridge → AirPods). RT callbacks must not malloc, lock, log, or do file I/O. No custom HAL driver, menu bar app, libsamplerate drift engine, or signing in this phase.

</domain>

<decisions>
## Implementation Decisions

### Process & deployment shape
- Standalone C++20 CLI daemon (`apm44-bridge`) spawned manually for MVP; no LaunchAgent yet
- BlackHole is external prerequisite (user-installed v0.6.1+); bridge fails fast with clear message if missing
- Device selection: CLI flags `--input-device` / `--output-device` with UID defaults; auto-pick BlackHole 2ch and first AirPods Max USB-C match when omitted
- Single process owns both HAL IOProcs (input @ 44100, output @ 48000); no Swift in RT path

### Core Audio I/O
- Raw HAL `AudioDeviceCreateIOProcID` + `AudioDeviceStart` (not AU HALOutput) for symmetric bridge
- Float32, 2ch, non-interleaved on both sides; negotiate stream formats explicitly before start
- Fixed block size target 512 frames @ 44.1 input where hardware allows; document actual buffer sizes in README
- Preallocate all callback buffers at start; ring buffer is simple fixed-capacity float planar (MVP: no drift control yet — fixed-ratio SRC only)

### Sample-rate conversion (MVP)
- `AudioConverter` (AudioToolbox C API) with persistent converter instance created once at startup
- Nominal ratio 48000/44100; prime with silence until first valid input
- On conversion failure: output silence for that buffer (no logging in callback); count xruns on background thread only

### Real-time safety
- C++20 only in `BridgeDaemon/` + `Shared/` for Phase 1
- No malloc/locks/logging/file I/O in IOProcs; spdlog or stderr logging on main thread only
- Device enumeration and format setup happen before `AudioDeviceStart`

### Documentation & validation
- `docs/mvp-routing.md` with Audio MIDI Setup screenshots checklist and DAW routing steps (Logic + Ableton)
- `scripts/verify-devices.sh` lists BlackHole @ 44100 and AirPods @ 48000 via `system_profiler` / `SwitchAudioSource` optional
- Success demo: play 440 Hz tone from DAW to BlackHole, hear tone on AirPods

### Claude's Discretion
- Exact repo layout under `BridgeDaemon/`, `Shared/`, `CMakeLists.txt` vs Xcode project
- Whether to use CMake + `xcodebuild` or pure Xcode gen — prefer CMake for agent-friendly builds if trivial
- Minor buffer sizing within 256–1024 frame range

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Greenfield repo; planning artifacts in `.planning/research/` (STACK.md, ARCHITECTURE.md) define module layout

### Established Patterns
- Target layout: `BridgeDaemon/` (RT engine), `Shared/` (formats, ring), future `App/` Swift shell in Phase 3
- MVP routing per PROJECT.md: DAW → BlackHole @ 44.1 → daemon → AirPods @ 48

### Integration Points
- Input: BlackHole 2ch device UID (Existential Audio)
- Output: AirPods Max USB-C device UID (user machine-specific)
- Phase 2 will replace fixed SRC with libsamplerate + drift; Phase 4 replaces BlackHole with HAL driver

</code_context>

<specifics>
## Specific Ideas

- Match research STACK.md: AudioToolbox `AudioConverter` in C++ daemon, not AVAudioConverter in Swift
- GPL BlackHole must not be vendored — document install link only
- Honest scope: no latency presets, meters, or hotplug in Phase 1

</specifics>

<deferred>
## Deferred Ideas

- libsamplerate + drift controller (Phase 2)
- Menu bar UI and XPC control (Phase 3)
- APM44Bridge.driver HAL plug-in (Phase 4)
- Developer ID signing and DAW matrix (Phase 5)
- LaunchAgent / login item auto-start

</deferred>
