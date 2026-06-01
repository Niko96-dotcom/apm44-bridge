# Roadmap: APM44 Bridge

## Overview

Deliver a macOS audio bridge that lets DAW users monitor 44.1 kHz sessions on AirPods Max USB-C at 48 kHz. Work proceeds in five vertical MVP slices: prove the BlackHole loopback path with AVAudioConverter, harden the engine with libsamplerate and drift control, ship a menu bar control surface, replace BlackHole with a custom HAL Audio Server Plug-in, then integrate and validate the full production stack with signing and DAW matrix testing.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: BlackHole Console Bridge** - End-to-end 44.1→48 loopback via AVAudioConverter CLI/daemon
- [ ] **Phase 2: Production SRC & Drift Engine** - libsamplerate, lock-free ring, drift controller, soak validation
- [ ] **Phase 3: Menu Bar Application** - SwiftUI shell with latency modes, hotplug, meters, honest latency reporting
- [ ] **Phase 4: HAL Virtual Device** - libASPL `APM44Bridge.driver` @ 44100 with IPC ring transport
- [ ] **Phase 5: Integration & Ship Readiness** - Full-stack DAW validation, signing, export-path verification

## Phase Details

### Phase 1: BlackHole Console Bridge
**Goal**: Producer can route DAW output through BlackHole @ 44.1 kHz and hear resampled audio on AirPods Max USB-C @ 48 kHz via a console bridge daemon
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: MVP-01, MVP-02, MVP-03, ENG-01, ENG-05, DEV-04
**Success Criteria** (what must be TRUE):
  1. User can play a 44.1 kHz DAW session to BlackHole 2ch and hear audio on AirPods Max USB-C without changing project sample rate
  2. Audio MIDI Setup shows BlackHole at 44,100 Hz and AirPods Max USB-C at 48,000 Hz while the bridge is running
  3. Bridge performs 44.1 kHz float → 48 kHz float conversion using AVAudioConverter or AudioToolbox with audible output and no sustained silence
  4. Documented manual routing steps exist: DAW → BlackHole @ 44.1; bridge reads BlackHole in → AirPods out @ 48
  5. Bridge audio callbacks run without malloc, locks, logging, or file I/O in the real-time path
**Plans**: 4 plans

Plans:
- [x] 01-01-PLAN.md — CMake scaffold, Shared ASBD helpers, CLI skeleton
- [x] 01-02-PLAN.md — HAL device discovery, format negotiation, verify-devices.sh
- [x] 01-03-PLAN.md — Planar ring, AudioConverter SRC, dual IOProcs, BridgeEngine
- [x] 01-04-PLAN.md — MVP routing docs, verify tooling, 440 Hz human demo

### Phase 2: Production SRC & Drift Engine
**Goal**: Bridge sustains long sessions without crackle, underrun, or latency creep using production-grade async SRC and drift correction
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: ENG-02, ENG-03, ENG-04, QA-01
**Success Criteria** (what must be TRUE):
  1. Bridge resamples with variable-ratio streaming SRC (160/147 nominal) using libsamplerate, not fixed-ratio-only conversion
  2. Lock-free ring buffer between input and output callbacks maintains a configurable target fill (~10–20 ms default)
  3. Drift controller adjusts effective SRC ratio within ±500 ppm bounds to prevent buffer runaway or starvation
  4. User can run 30+ minutes of continuous 44.1 → 48 playback without crackle, drift-induced underrun, or unbounded latency growth
**Plans**: TBD

### Phase 3: Menu Bar Application
**Goal**: User controls and monitors the bridge from a menu bar app with latency presets, device selection, and hotplug resilience
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: APP-01, APP-02, APP-03, APP-04, APP-05, QA-03
**Success Criteria** (what must be TRUE):
  1. Menu bar icon shows bridge running/stopped state and the selected physical output device
  2. User can choose latency mode: Low (~6–8 ms), Balanced (~12–18 ms, default), or Safe mixing (~25–40 ms)
  3. User can pick SRC quality tier aligned with the selected latency mode (medium/high/best)
  4. AirPods connect/disconnect is handled without requiring DAW restart when feasible
  5. Status meter shows buffer fill and glitch indicators; round-trip monitoring latency is reported honestly (no zero-latency claim)
**Plans**: TBD
**UI hint**: yes

### Phase 4: HAL Virtual Device
**Goal**: DAW sees a native **APM44 Bridge** virtual output at 44.1 kHz that hands buffers to the user-space daemon via IPC
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: DEV-01, DEV-02, DEV-03, DRV-01, DRV-02, DRV-03
**Success Criteria** (what must be TRUE):
  1. User can select **APM44 Bridge** (2ch, Float32, 44,100 Hz) in Audio MIDI Setup and the DAW without BlackHole installed
  2. HAL Audio Server Plug-in `APM44Bridge.driver` exposes device UID `com.niko.apm44.bridge.device` advertising 44100 Hz only
  3. Driver does not open or control AirPods hardware; all SRC and physical output remain in the user-space bridge
  4. Driver hands audio buffers to the bridge daemon via documented IPC/shared-memory ring transport
  5. User can set DAW/session project rate to 44.1 kHz with output routed to APM44 Bridge in Logic, Ableton, and similar hosts
**Plans**: TBD

### Phase 5: Integration & Ship Readiness
**Goal**: Full production stack is validated across DAWs, export paths stay honest, and artifacts are signed for distribution
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: QA-02
**Success Criteria** (what must be TRUE):
  1. DAW export/stem bounce at 44.1 kHz project rate produces 44.1 kHz files (monitoring path does not alter bounce sample rate)
  2. End-to-end workflow validated: DAW @ 44.1 → APM44 Bridge → daemon → AirPods @ 48 with 30+ minute stability
  3. DAW validation matrix passes for Logic and Ableton (minimum); Audio MIDI Setup confirms 44.1 on bridge, 48 kHz on AirPods
  4. HAL driver bundle and menu bar app are Developer ID signed and ready for notarization/distribution testing
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. BlackHole Console Bridge | 0/4 | Not started | - |
| 2. Production SRC & Drift Engine | 0/TBD | Not started | - |
| 3. Menu Bar Application | 0/TBD | Not started | - |
| 4. HAL Virtual Device | 0/TBD | Not started | - |
| 5. Integration & Ship Readiness | 0/TBD | Not started | - |
