# Requirements: APM44 Bridge

**Defined:** 2026-06-01
**Core Value:** DAW sessions stay at 44.1 kHz while monitoring stably on AirPods Max USB-C at 48 kHz via a virtual bridge endpoint.

## v1 Requirements

### Virtual device & DAW integration

- [ ] **DEV-01**: User can select a stereo output device that reports **44,100 Hz** nominal rate in Audio MIDI Setup and the DAW
- [ ] **DEV-02**: Virtual device exposes **2 channels**, **Float32** format suitable for DAW routing
- [ ] **DEV-03**: User can set DAW/session project sample rate to **44.1 kHz** with output routed to the bridge device (Logic, Ableton, and similar hosts)
- [x] **DEV-04**: Physical AirPods Max USB-C endpoint remains at **48,000 Hz** in Audio MIDI Setup while bridge is active

### Bridge engine (audio path)

- [x] **ENG-01**: Bridge captures 44.1 kHz float audio from the virtual/loopback input path and plays 48 kHz float to AirPods Max USB-C output
- [x] **ENG-02**: Sample-rate conversion supports the **160/147** nominal ratio with **variable-ratio** streaming SRC for clock drift
- [x] **ENG-03**: Lock-free ring buffer sits between input and output callbacks with a configurable target fill level (~10–20 ms default)
- [x] **ENG-04**: Drift controller adjusts effective SRC ratio within bounded PPM (e.g. ±500 ppm) to prevent long-run underrun, overflow, or latency creep
- [x] **ENG-05**: Real-time callbacks avoid malloc, locks, logging, file I/O, device enumeration, and UI mutation

### MVP (BlackHole proof)

- [x] **MVP-01**: Bridge runs with **BlackHole 2ch @ 44.1 kHz** as input and **AirPods Max USB-C @ 48 kHz** as output
- [x] **MVP-02**: MVP uses **AVAudioConverter** or AudioToolbox `AudioConverter` for initial SRC before libsamplerate swap
- [x] **MVP-03**: Documented manual routing: DAW → BlackHole @ 44.1; bridge BlackHole in → AirPods out @ 48

### Production driver

- [ ] **DRV-01**: HAL **Audio Server Plug-in** `APM44Bridge.driver` exposes device **APM44 Bridge** (UID `com.niko.apm44.bridge.device`)
- [ ] **DRV-02**: Driver advertises **44100 Hz only** in available nominal rates; does **not** open or control AirPods hardware
- [ ] **DRV-03**: Driver hands audio buffers to user-space bridge via documented IPC/shared-memory transport (ring transport)

### Application & UX

- [ ] **APP-01**: Menu bar app shows bridge **running/stopped** state and selected physical output device
- [ ] **APP-02**: User can pick **latency mode**: Low (~6–8 ms target buffer), Balanced (~12–18 ms, default), Safe mixing (~25–40 ms)
- [ ] **APP-03**: User can pick SRC quality tier aligned with latency mode (medium/high/best)
- [ ] **APP-04**: App handles **device hotplug** (AirPods connect/disconnect) without requiring DAW restart when feasible
- [ ] **APP-05**: Status meter shows buffer fill / glitch indicators for troubleshooting

### Quality & validation

- [x] **QA-01**: **30+ minute** continuous playback at 44.1 → 48 without crackle, drift-induced underrun, or unbounded latency growth
- [ ] **QA-02**: DAW **export/stem** remains **44.1 kHz** when project rate is 44.1 (monitoring path does not alter bounce sample rate)
- [ ] **QA-03**: Measured/reportable **round-trip monitoring latency** is surfaced honestly (no “zero latency” claim)

## v2 Requirements

### Pro Tools & advanced routing

- **PT-01**: Optional **APM44 Bridge Pro** unified virtual playback engine (44.1 in/out mirror) for single-device Pro Tools workflows
- **PT-02**: Mirrored input from user-selected 44.1 interface for record monitoring paths

### Product polish

- **POL-01**: Notarization, installer, and signed driver distribution pipeline
- **POL-02**: Automated latency calibration wizard per machine

## Out of Scope

| Feature | Reason |
|---------|--------|
| Set AirPods nominal rate to 44.1 kHz | Hardware exposes 48 kHz only; Core Audio will refuse |
| Aggregate / Multi-Output Device routing | Non-deterministic; conflicts with single SRC path goal |
| Ship BlackHole source inside closed app | GPL-3.0; MVP depends on user-installed BlackHole |
| Bluetooth-only AirPods path | USB-C wired 48 kHz scope for v1 |
| Windows/Linux ports | macOS Core Audio only for v1 |
| In-driver SRC or AirPods I/O | Driver stays minimal; bridge daemon owns complexity |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DEV-01 | Phase 4 | Pending |
| DEV-02 | Phase 4 | Pending |
| DEV-03 | Phase 4 | Pending |
| DEV-04 | Phase 1 | Complete |
| ENG-01 | Phase 1 | Complete |
| ENG-02 | Phase 2 | Complete |
| ENG-03 | Phase 2 | Complete |
| ENG-04 | Phase 2 | Complete |
| ENG-05 | Phase 1 | Complete |
| MVP-01 | Phase 1 | Complete |
| MVP-02 | Phase 1 | Complete |
| MVP-03 | Phase 1 | Complete |
| DRV-01 | Phase 4 | Pending |
| DRV-02 | Phase 4 | Pending |
| DRV-03 | Phase 4 | Pending |
| APP-01 | Phase 3 | Pending |
| APP-02 | Phase 3 | Pending |
| APP-03 | Phase 3 | Pending |
| APP-04 | Phase 3 | Pending |
| APP-05 | Phase 3 | Pending |
| QA-01 | Phase 2 | Complete |
| QA-02 | Phase 5 | Pending |
| QA-03 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23/23 ✓
- Unmapped: 0

---
*Requirements defined: 2026-06-01*
*Last updated: 2026-06-01 after initial definition*
