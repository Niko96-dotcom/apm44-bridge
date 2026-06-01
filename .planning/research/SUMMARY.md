# Research Summary

**Project:** APM44 Bridge
**Synthesized:** 2026-06-01

## Executive Summary

Build a **macOS-only** product with two layers: (1) a **44.1 kHz virtual output** the DAW trusts, and (2) a **user-space C++ bridge** that resamples to **48 kHz** for AirPods Max USB-C. MVP proves the audio path with **user-installed BlackHole**; production replaces loopback with a **HAL Audio Server Plug-in** built via **libASPL**, keeping SRC and hardware I/O in the daemon. **libsamplerate** with drift-aware `src_ratio` is the production SRC; **AVAudioConverter** is acceptable for the first spike.

## Stack (decisions)

- **RT engine:** C++20 + Core Audio IOProcs
- **MVP virtual sink:** BlackHole 2ch @ 44100 (external, GPL — not embedded)
- **Production virtual sink:** `APM44Bridge.driver` (libASPL, MIT)
- **SRC:** AVAudioConverter (MVP) → libsamplerate SINC (production)
- **UI:** SwiftUI menu bar app (non-RT)
- **Build:** CMake + Xcode; Developer ID signing for HAL bundle

## Table Stakes

- 44.1 kHz stereo virtual output visible to DAW and Audio MIDI Setup
- AirPods USB-C stays at 48 kHz
- Long-session stability (drift control, no latency creep)
- Float32 2ch, honest latency modes
- No Aggregate/Multi-Output hacks; no forcing hardware rate

## Architecture

Vertical slices: **console bridge → drift/SRC → UI → custom driver**. Driver is a thin ring transport; daemon owns resampler, drift controller, and AirPods output client.

## Watch Out For

1. **Clock drift** — #1 gremlin; variable-ratio SRC mandatory
2. **RT safety** — no alloc/locks in callbacks
3. **GPL BlackHole** — dependency only for MVP
4. **HAL signing** on modern macOS — plan Developer ID early for Phase 4
5. **Scope:** Pro Tools unified engine is v2, not v1

## Recommended Roadmap Shape

1. BlackHole proof + AVAudioConverter routing
2. libsamplerate + drift controller + soak tests
3. Menu bar app + latency presets + hotplug
4. libASPL virtual device @ 44100 + IPC ring
5. Polish, signing, DAW validation matrix

## Files

- `STACK.md` — technologies and anti-patterns
- `FEATURES.md` — table stakes / differentiators / anti-features
- `ARCHITECTURE.md` — components, data flow, build order
- `PITFALLS.md` — domain-specific failure modes
