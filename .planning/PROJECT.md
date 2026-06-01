# APM44 Bridge

## What This Is

APM44 Bridge is a macOS audio product that lets DAW users (Logic, Ableton, Pro Tools, etc.) run **44.1 kHz** sessions while monitoring through **AirPods Max USB-C at 48 kHz**. The DAW sees a virtual Core Audio output device named **APM44 Bridge** (2ch, Float32, 44,100 Hz). A user-space bridge daemon resamples 44.1 → 48, handles clock drift, and plays to the physical AirPods endpoint. The headphones are **not** retuned to 44.1 kHz—the software lies upstream to the DAW, not downstream to the hardware.

## Core Value

A producer can set session/project rate to **44.1 kHz**, select **APM44 Bridge** as output, and hear stable, low-glitch monitoring on AirPods Max USB-C at **48 kHz** for long sessions—without changing exports, stems, plug-in oversampling assumptions, or project metadata.

## Current Milestone: v1.1 Production Sign-Off

**Goal:** Close v1.0 audit gaps so a producer can run **Cubase 15** @ 44.1 kHz → **APM44 Bridge** (HAL) → AirPods Max USB-C @ 48 kHz with signed/notarized binaries and documented human QA.

**Target features:**
- AMS + Cubase 15 enumerate and route to APM44 Bridge @ 44.1 kHz (DEV-01, DEV-03)
- Menu bar spawns `--virtual-device` when HAL driver is installed; BlackHole path remains supported fallback
- DRV-02: Harden driver to **44100 Hz only** in available nominal rates
- QA-02: Cubase export/bounce remains 44.1 kHz (`validate-export-rate.sh`)
- Developer ID sign + notarytool dry-run; signed HAL loads on a real Mac (hard gate for milestone done)
- **30+ minute** live monitoring soak on the HAL path (required)

**Key context:** Primary DAW sign-off matrix is **Cubase 15** (operator does not have Logic/Ableton). Signing is required for v1.1 complete—not docs-only.

## Current State (v1.0 shipped 2026-06-01)

**Shipped:** Five-phase vertical MVP — CMake monorepo, `apm44-bridge` daemon (BlackHole + `--virtual-device` paths), SwiftUI menu bar app, `APM44Bridge.driver` HAL plug-in with POSIX shm ring, integration docs/scripts.

**Code-complete paths:**
- MVP: DAW → BlackHole @ 44.1 → bridge → AirPods @ 48 (libsamplerate + drift PI)
- Production HAL: DAW → APM44 Bridge @ 44.1 → driver → shm → daemon → AirPods @ 48 (CLI `--virtual-device`)

**Human sign-off deferred:** DAW matrix, export bounce (QA-02), signed driver load, 30+ min live soak, notarization dry-run. See `.planning/milestones/v1.0-MILESTONE-AUDIT.md`.

**Scale:** ~164 files, ~12k LOC added in milestone window (2026-06-01).

## Requirements

### Validated

- ✓ Bridge reads 44.1 kHz float and outputs 48 kHz to AirPods Max USB-C — v1.0 (ENG-01)
- ✓ Variable-ratio streaming SRC (160/147 nominal) with libsamplerate — v1.0 (ENG-02)
- ✓ Lock-free SPSC ring with configurable target fill — v1.0 (ENG-03)
- ✓ Drift controller with ±500 ppm bounds — v1.0 (ENG-04)
- ✓ RT callbacks free of malloc/locks/logging — v1.0 (ENG-05)
- ✓ BlackHole MVP routing path — v1.0 (MVP-01, MVP-02, MVP-03)
- ✓ AirPods remain @ 48 kHz in AMS while bridge active — v1.0 (DEV-04)
- ✓ Menu bar app: state, presets, device picker, hotplug, meters, honest latency — v1.0 (APP-01–APP-05, QA-03)
- ✓ Automated soak harness + 60 s offline validation — v1.0 (QA-01 auto layer)
- ✓ HAL driver bundle builds with UID `com.niko.apm44.bridge.device` — v1.0 (DRV-01)
- ✓ Shm IPC ring transport driver → daemon — v1.0 (DRV-03)
- ✓ Virtual device 2ch Float32 format — v1.0 (DEV-02, build evidence)

### Active (v1.1 — see Current Milestone)

Tracked in `.planning/REQUIREMENTS.md` (DEV-01, DEV-03, DRV-02, QA-02, APP integration, SHIP signing, QA soak).

### Out of Scope

- Forcing AirPods nominal rate to 44.1 kHz via `kAudioDevicePropertyNominalSampleRate` — hardware exposes 48 kHz only
- Aggregate / Multi-Output Device routing hacks — want one virtual 44.1 sink and one controlled SRC path
- Bundling BlackHole GPL code in a closed-source product without separate licensing — MVP may *use* installed BlackHole; production uses own driver
- Promising zero added latency — bridge adds buffering + SRC delay by design
- Pro Tools full virtual playback engine (**APM44 Bridge Pro**) — v2; v1 targets standard output-device workflow
- Bluetooth-only AirPods path — USB-C wired 48 kHz scope for v1
- Windows/Linux ports — macOS Core Audio only

## Context

**Problem:** AirPods Max USB-C wired lossless mode is documented as 24-bit / 48 kHz. Audio MIDI Setup only offers rates the hardware supports. DAWs at 44.1 kHz cannot honestly monitor through that endpoint without sample-rate conversion somewhere.

**Mental model:** APM44 Bridge changes what the **DAW thinks** it is connected to—not what the AirPods are.

**Architecture (shipped):**

```
DAW @ 44.1 kHz
   → Virtual device "APM44 Bridge" @ 44.1 kHz (HAL Audio Server Plug-in)
   → Bridge daemon (ring buffer, async SRC, drift control)
   → AirPods Max USB-C @ 48 kHz
```

**MVP routing (BlackHole — still supported):**

```
DAW → BlackHole 2ch @ 44.1 → Bridge app input @ 44.1
Bridge app output → AirPods Max USB-C @ 48
```

**Module layout:**

- `Driver/APM44Bridge.driver/` — libASPL virtual device, shm producer
- `BridgeDaemon/` — Core Audio clients, BridgeEngine, LibSamplerateSrc, DriftController
- `App/` — SwiftUI menu bar: device picker, latency/quality, meters
- `Shared/` — ASBD helpers, SPSC ring, shm layout

**Tech debt (from v1.0 audit):** Menu bar spawns BlackHole path only; unsigned HAL load not CI-verified; driver stream SInt16 vs float32 hardening; XPC daemon control deferred.

## Constraints

- **Platform**: macOS only — Core Audio, HAL Audio Server Plug-in for production virtual device
- **Driver pattern**: Audio Server Driver Plug-in (not AudioDriverKit for virtual device per Apple guidance)
- **Formats**: Float32, non-interleaved, 2 channels; virtual device **44100 only** in production driver
- **Real-time**: Audio callbacks — no malloc, locks, logging, Swift ARC churn, Obj-C messaging, file I/O, device enumeration, UI mutation
- **Licensing**: BlackHole is GPL-3.0 — do not fork/ship inside closed app without compliance strategy
- **Hardware**: AirPods Max USB-C fixed 48 kHz endpoint; bridge must not open AirPods from inside the driver

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Lie upstream (virtual 44.1) not downstream (force 48 kHz device to 44.1) | AirPods USB-C exposes 48 kHz only; Core Audio correctly refuses unsupported nominal rates | ✓ Good — HAL driver advertises 44100 |
| MVP: BlackHole loopback before custom HAL driver | Proves SRC + drift + routing without driver development risk | ✓ Good — Phase 1 complete |
| Production: `APM44Bridge.driver` + user-space bridge | Driver stays boring; SRC/drift/AirPods I/O in daemon | ✓ Good — build complete; manual QA pending |
| MVP SRC: AVAudioConverter; production: libsamplerate | Apple APIs fine for POC; libsamplerate supports variable `src_ratio` for drift | ✓ Good — default path is libsamplerate |
| C++ for RT engine, Swift for shell | RT safety vs UI/productivity | ✓ Good |
| Vertical MVP phases | End-to-end slices (BlackHole bridge → drift → UI → custom driver) | ✓ Good — v1.0 shipped |
| Subprocess bridge control (not XPC) | Faster MVP; defer IPC hardening | ⚠️ Revisit — wire `--virtual-device` in app |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-01 — milestone v1.1 Production Sign-Off started*
