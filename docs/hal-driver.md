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
./scripts/reload-coreaudio.sh   # sudo killall coreaudiod — kickstart is blocked on macOS 14.4+
./scripts/verify-hal-driver.sh
```

Install copies the bundle to `/Library/Audio/Plug-Ins/HAL/`. **Production:** use signed + notarized driver (`scripts/sign-release.sh`, `scripts/notarize-hal-driver.sh`). On macOS 15+, unsigned HAL plug-ins fail to load.

## Sample rate contract (44100 only)

The driver calls `SetAvailableSampleRatesAsync({44100, 44100})` so Audio MIDI Setup offers **only 44,100 Hz** as a nominal rate. DAWs cannot negotiate 48 kHz on the virtual device.

## Runtime routing

1. **Audio MIDI Setup** — confirm **APM44 Bridge** at 44,100 Hz; AirPods Max USB-C at 48,000 Hz.
2. **Menu bar app** — start bridge; when HAL is detected, spawns `apm44-bridge --virtual-device` automatically.
3. **DAW (Cubase 15)** — project **44.1 kHz**, output **APM44 Bridge**, Control Room L/R ports assigned ([first-run-cubase.md](first-run-cubase.md)).

CLI equivalent:

```bash
build/BridgeDaemon/apm44-bridge --virtual-device --output-device "<AirPods UID>"
```

Or: `bash scripts/start-virtual-bridge.sh`

## IPC

- Shm name: `/apm44_bridge_ring` (see `Shared/include/apm44/ShmRingLayout.h`)
- Driver: producer (ring created at driver load in `ShmIoHandler` constructor)
- Daemon: consumer (`--virtual-device` → ring drain)
- Shm mode **0666** so coreaudiod (driver) and user daemon can share the ring

## Related

- [Release signing](release.md)
- [Cubase first-run](first-run-cubase.md)
- [verify-hal-driver.sh](../scripts/verify-hal-driver.sh)
