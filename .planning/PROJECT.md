# APM44 Bridge

## What This Is

APM44 Bridge is a macOS audio product that lets DAW users (Logic, Ableton, Pro Tools, etc.) run **44.1 kHz** sessions while monitoring through **AirPods Max USB-C at 48 kHz**. The DAW sees a virtual Core Audio output device named **APM44 Bridge** (2ch, Float32, 44,100 Hz). A user-space bridge daemon resamples 44.1 → 48, handles clock drift, and plays to the physical AirPods endpoint. The headphones are **not** retuned to 44.1 kHz—the software lies upstream to the DAW, not downstream to the hardware.

## Core Value

A producer can set session/project rate to **44.1 kHz**, select **APM44 Bridge** as output, and hear stable, low-glitch monitoring on AirPods Max USB-C at **48 kHz** for long sessions—without changing exports, stems, plug-in oversampling assumptions, or project metadata.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Virtual 44.1 kHz stereo output visible to Core Audio / DAW as **APM44 Bridge**
- [ ] Bridge reads 44.1 kHz float audio and outputs 48 kHz to AirPods Max USB-C
- [ ] Asynchronous SRC with drift correction (no long-run crackle/underrun/latency creep)
- [ ] MVP path: BlackHole 2ch @ 44.1 in → AirPods @ 48 out (prove routing before custom driver)
- [ ] Production path: HAL Audio Server Plug-in (`APM44Bridge.driver`) + separate bridge daemon
- [ ] Real-time audio path: no malloc/locks/logging in callbacks; C++ engine + Swift menu app shell
- [ ] Latency modes: Low / Balanced / Safe mixing with honest latency reporting
- [ ] Device hotplug handling and status UI (menu bar app)
- [ ] Success validation: DAW + Audio MIDI Setup show 44.1 on bridge, 48 kHz on AirPods; long playback stable

### Out of Scope

- Forcing AirPods nominal rate to 44.1 kHz via `kAudioDevicePropertyNominalSampleRate` — hardware exposes 48 kHz only
- Aggregate / Multi-Output Device routing hacks — want one virtual 44.1 sink and one controlled SRC path
- Bundling BlackHole GPL code in a closed-source product without separate licensing — MVP may *use* installed BlackHole; production uses own driver
- Promising zero added latency — bridge adds buffering + SRC delay by design
- Pro Tools full virtual playback engine (**APM44 Bridge Pro**) — v2; v1 targets standard output-device workflow

## Context

**Problem:** AirPods Max USB-C wired lossless mode is documented as 24-bit / 48 kHz. Audio MIDI Setup only offers rates the hardware supports. DAWs at 44.1 kHz cannot honestly monitor through that endpoint without sample-rate conversion somewhere.

**Mental model:** APM44 Bridge changes what the **DAW thinks** it is connected to—not what the AirPods are.

**Architecture (target):**

```
DAW @ 44.1 kHz
   → Virtual device "APM44 Bridge" @ 44.1 kHz (HAL Audio Server Plug-in)
   → Bridge daemon (ring buffer, async SRC, drift control)
   → AirPods Max USB-C @ 48 kHz
```

**MVP routing (BlackHole):**

```
DAW → BlackHole 2ch @ 44.1 → Bridge app input @ 44.1
Bridge app output → AirPods Max USB-C @ 48
```

**Nominal block ratio:** 48000/44100 = 160/147 (147 input frames → 160 output frames at nominal rates). Still requires variable-ratio SRC for clock drift.

**Module layout (suggested):**

- `Driver/APM44Bridge.driver/` — boring virtual device, hands buffers to user-space
- `BridgeDaemon/` — Core Audio clients, `AudioBridge`, `Resampler`, `DriftController`
- `App/` — SwiftUI menu bar: device picker, latency/quality, meters
- `Shared/` — formats, lock-free ring, logging (non-RT)

**Resampler strategy:** MVP `AVAudioConverter` or AudioToolbox; production **libsamplerate** with streaming `src_ratio` adjustment.

**Drift control:** Ring buffer target fill ~10–20 ms; small PPM correction on consumption rate (±500 ppm cap).

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
| Lie upstream (virtual 44.1) not downstream (force 48 kHz device to 44.1) | AirPods USB-C exposes 48 kHz only; Core Audio correctly refuses unsupported nominal rates | — Pending |
| MVP: BlackHole loopback before custom HAL driver | Proves SRC + drift + routing without driver development risk | — Pending |
| Production: `APM44Bridge.driver` + user-space bridge | Driver stays boring; SRC/drift/AirPods I/O in daemon | — Pending |
| MVP SRC: AVAudioConverter; production: libsamplerate | Apple APIs fine for POC; libsamplerate supports variable `src_ratio` for drift | — Pending |
| C++ for RT engine, Swift for shell | RT safety vs UI/productivity | — Pending |
| Vertical MVP phases | End-to-end slices (BlackHole bridge → drift → UI → custom driver) | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-01 after initialization*
