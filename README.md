# APM44 Bridge

macOS console bridge: **BlackHole 2ch @ 44.1 kHz** → resample → **AirPods Max USB-C @ 48 kHz**.

Phase 1 delivers `apm44-bridge` (C++20 CLI). No custom HAL driver, menu bar app, or drift engine yet.

## Prerequisites

- macOS 14+
- Xcode Command Line Tools
- CMake 3.28+
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole/releases) v0.6.1+ (user-installed, GPL-3.0 — **not bundled**)

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure
```

Binary: `build/BridgeDaemon/apm44-bridge`

## Pre-flight

```bash
bash scripts/verify-devices.sh
./build/BridgeDaemon/apm44-bridge --preflight
```

Set **BlackHole 2ch** to **44100 Hz** and **AirPods** to **48000 Hz** in Audio MIDI Setup before running.

## Run

```bash
./build/BridgeDaemon/apm44-bridge
```

Options: `--help`, `--list-devices`, `--preflight`, `--print-config`, `--input-device UID`, `--output-device UID`.

## Documentation

- [BlackHole prerequisite](docs/blackhole-prerequisite.md)
- [MVP routing (Logic + Ableton)](docs/mvp-routing.md)

## Scope (Phase 1)

- AudioToolbox `AudioConverter` (fixed 44.1 → 48 ratio, no drift control)
- RT-safe IOProcs (no malloc/locks/logging in callbacks)
- External BlackHole only — no GPL vendoring
