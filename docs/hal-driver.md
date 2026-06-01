# HAL virtual device (APM44 Bridge)

Phase 4 adds **`APM44Bridge.driver`**, a Core Audio HAL Audio Server Plug-in that exposes **APM44 Bridge** at **44.1 kHz** stereo. The DAW plays to this device; audio is copied into a POSIX shared-memory ring. The user-space daemon reads that ring and continues 44.1 → 48 kHz SRC to AirPods.

BlackHole is **not** required when this path is fully installed and loaded.

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target APM44Bridge apm44-bridge
```

Artifacts:

- `build/Driver/APM44Bridge.driver`
- `build/BridgeDaemon/apm44-bridge`

## Install (development)

```bash
./scripts/install-driver.sh
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
./scripts/verify-hal-driver.sh
```

Install copies the bundle to `/Library/Audio/Plug-Ins/HAL/`. **Developer ID signing and notarization are Phase 5.** On macOS 15+, unsigned HAL plug-ins may fail to load until signed.

## Runtime routing

1. **Audio MIDI Setup** — confirm **APM44 Bridge** at 44,100 Hz; AirPods Max USB-C at 48,000 Hz.
2. **DAW** — project/session **44.1 kHz**, output device **APM44 Bridge**.
3. **Daemon** — start the bridge in virtual-device mode (no BlackHole input HAL client):

```bash
build/BridgeDaemon/apm44-bridge --virtual-device --output-device "<AirPods UID>"
```

Use `--list-devices` to find the AirPods UID. The menu bar app still defaults to BlackHole until Phase 5 wires `--virtual-device`.

## IPC

- Shm name: `/apm44_bridge_ring` (see `Shared/include/apm44/ShmRingLayout.h`)
- Driver: producer (`OnWriteMixedOutput` → `MmapShmRing::pushInterleaved`)
- Daemon: consumer (`--virtual-device` → `VirtualDeviceFeed::drainTo`)

## Known gaps (Phase 4 skeleton)

- Nominal-rate list may not be restricted to 44100-only in all hosts until driver properties are hardened
- End-to-end DAW + HAL load requires manual QA and often a reboot on first install
- Menu bar app does not pass `--virtual-device` yet
