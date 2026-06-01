# APM44 Bridge menu bar app

## Prerequisites

- macOS 14+
- Xcode 16 (or 15.4+)
- CMake build of the bridge daemon:

```bash
cmake -S . -B build
cmake --build build
```

## Configure daemon path

```bash
export APM44_BRIDGE_PATH="$PWD/build/BridgeDaemon/apm44-bridge"
# Optional: repo root for DEBUG builds without env
export APM44_DEV_REPO_ROOT="$PWD"
```

## Build the app

```bash
bash scripts/verify-app-build.sh
```

Or open `App/APM44Bridge.xcodeproj` in Xcode and run the **APM44 Bridge** scheme.

## BlackHole

Install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole/releases) separately and set **44.1 kHz** in Audio MIDI Setup. The app does not bundle BlackHole (GPL-3.0).

## Human QA

See `docs/menu-bar-qa.md` for hardware validation steps.
