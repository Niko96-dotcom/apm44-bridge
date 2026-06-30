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

To rebuild, stop any running copy, and open the exact local build:

```bash
bash scripts/rebuild-and-open-app.sh
```

Or open `App/APM44Bridge.xcodeproj` in Xcode and run the **APM44 Bridge** scheme.

## User controls

The menu bar panel owns normal bridge lifecycle actions:

- **Start** launches the bridge against the selected output device.
- **Stop** stops app-owned bridge work.
- **Restart** restarts the app-owned bridge path.
- **Quit APM44 Bridge** stops app-owned bridge work, then exits the app.

Quit is intentionally an app lifecycle action only. It does not install,
uninstall, reload, or otherwise mutate the HAL driver.

## BlackHole

Install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole/releases) separately and set **44.1 kHz** in Audio MIDI Setup. The app does not bundle BlackHole (GPL-3.0).

## Human QA

See `docs/menu-bar-qa.md` for hardware validation steps.
