# APM44 Bridge

macOS audio bridge: DAW sessions stay at **44.1 kHz** while monitoring through **AirPods Max USB-C at 48 kHz**.

| Phase | Status | What ships |
|-------|--------|------------|
| 1 — BlackHole console bridge | ✓ | `apm44-bridge` CLI, AudioToolbox SRC MVP |
| 2 — Production SRC & drift | ✓ | libsamplerate, drift controller, offline soak |
| 3 — Menu bar app | ✓ | **APM44 Bridge** SwiftUI app, latency/SRC presets, meters |
| 4 — HAL virtual device | planned | `APM44Bridge.driver` @ 44100 (no BlackHole) |
| 5 — Integration & ship readiness | in progress | DAW matrix, export QA, signing docs |

**MVP path today:** DAW → **BlackHole 2ch @ 44100** → `apm44-bridge` → **AirPods @ 48000**.

## Prerequisites

- macOS 14+
- Xcode Command Line Tools (Xcode 16.x for menu bar app)
- CMake 3.28+
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole/releases) v0.6.1+ for MVP routing (GPL-3.0 — **not bundled**)
- AirPods Max USB-C @ **48000 Hz** for monitoring

## Build & test

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

Binaries:

- `build/BridgeDaemon/apm44-bridge` — bridge daemon
- `build/BridgeDaemon/apm44-soak` — offline soak harness

Menu bar app (XcodeGen):

```bash
bash scripts/verify-app-build.sh
```

## Pre-flight

```bash
bash scripts/verify-devices.sh
./build/BridgeDaemon/apm44-bridge --preflight
```

Set **BlackHole 2ch** to **44100 Hz** and **AirPods** to **48000 Hz** in Audio MIDI Setup.

## Run

**CLI:**

```bash
./build/BridgeDaemon/apm44-bridge
```

Options: `--help`, `--list-devices`, `--preflight`, `--print-config`, `--metrics-json`, `--target-fill-ms`, `--src-quality`, `--input-device UID`, `--output-device UID`.

**Menu bar app:** launch **APM44 Bridge** from Xcode or the built `.app`; set `APM44_BRIDGE_PATH` to the daemon binary if not embedded.

## Documentation

| Doc | Purpose |
|-----|---------|
| [MVP routing (Logic + Ableton)](docs/mvp-routing.md) | BlackHole signal path |
| [DAW validation matrix](docs/daw-matrix.md) | Logic/Ableton checklist + QA sign-off |
| [Export rate validation (QA-02)](scripts/validate-export-rate.sh) | Bounce stays 44100 Hz |
| [Soak test (QA-01)](docs/soak-test.md) | 30+ min stability |
| [Menu bar app](docs/menu-bar-app.md) | App architecture |
| [Menu bar hardware QA](docs/menu-bar-qa.md) | APP-01–05 checklist |
| [Release signing](docs/release.md) | Developer ID, `notarytool`, HAL install |
| [BlackHole prerequisite](docs/blackhole-prerequisite.md) | MVP install |

## Verification scripts

```bash
bash scripts/verify-devices.sh
bash scripts/verify-menu-bar.sh
bash scripts/validate-export-rate.sh --instructions
bash scripts/ci-soak.sh
```

## Distribution (preview)

- Sign with **Developer ID Application** + hardened runtime — see [docs/release.md](docs/release.md)
- HAL driver dev install: `bash scripts/install-driver.sh` (ad-hoc; Phase 4 build required)
- Notarization: `xcrun notarytool submit` on a zip/dmg container, then `xcrun stapler staple`

## License / dependencies

- BlackHole: user-installed, GPL-3.0 — not vendored
- libsamplerate: BSD-2-Clause (submodule)
