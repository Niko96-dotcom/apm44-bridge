# HAL virtual device (APM44 Bridge)

Phase 4 adds **`APM44Bridge.driver`**, a Core Audio HAL Audio Server Plug-in that exposes **APM44 Bridge** at **44.1 kHz** stereo. The DAW plays to this device; audio is copied into a POSIX shared-memory ring. The user-space daemon reads that ring and continues 44.1 → 48 kHz SRC to AirPods.

BlackHole is **not** required when this path is fully installed and loaded.

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build --target APM44Bridge apm44-bridge apm44-hal-smoke
```

Artifacts:

- `build/Driver/APM44Bridge.driver`
- `build/BridgeDaemon/apm44-bridge`
- `build/BridgeDaemon/apm44-hal-smoke`

## Install (development)

```bash
./scripts/install-driver.sh
./scripts/verify-hal-driver.sh
```

Install copies the bundle to `/Library/Audio/Plug-Ins/HAL/`, verifies the installed executable hash, and reloads Core Audio. `verify-hal-driver.sh` fails if the installed HAL executable differs from the current build and, when APM44 Bridge is visible, runs `apm44-hal-smoke` to start the Core Audio device and prove the driver creates a readable shared-memory ring. **Production:** use signed + notarized driver (`scripts/sign-release.sh`, `scripts/notarize-hal-driver.sh`). On macOS 15+, unsigned HAL plug-ins fail to load.

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

Single-shot IPC check:

```bash
build/BridgeDaemon/apm44-bridge --shm-status
```

The helper and driver both include an `APM44_BUILD_ID` fingerprint. The driver writes its build ID into the shm header, and `--shm-status` / `apm44-hal-smoke` report both IDs so stale driver/helper pairs are visible immediately.

## IPC

- Shm name: `/apm44_bridge_ring` (see `Shared/include/apm44/ShmRingLayout.h`)
- Driver: producer (ring created at driver load in `ShmIoHandler` constructor)
- Daemon: consumer (`--virtual-device` → ring drain)
- Shm mode **0666** so coreaudiod (driver) and user daemon can share the ring
- Hard validation gates: ring magic, ABI version, header size, declared
  capacity/object size, channel count, fixed 44,100 Hz sample rate, and producer
  build ID. Mismatches fail fast instead of waiting for DAW playback.
- Diagnostic/stale-mapping evidence: driver generation and shm object identity
  (`st_dev`, `st_ino`, size) are reported and used to detect a ring that was
  replaced after the daemon mapped it.
- Tests must construct `MmapShmRing` with a short per-test shm name and must never create/unlink the production `/apm44_bridge_ring`.

### Security / local IPC

`/apm44_bridge_ring` is local-machine IPC. It is not an authentication or privilege boundary, and it should not be described as one.

The shm object currently uses mode **0666** so the HAL plug-in running in
`coreaudiod` and the user-space daemon can open the same ring without a separate
installer-owned broker. That means other local users or processes may be able to
open the object while it exists. The ring must contain audio/control state only;
do not put secrets, credentials, account identifiers, or authorization decisions
in shared memory.

Current mitigations are integrity-oriented rather than access-control-oriented:
the ring header carries ABI, sample-rate, build-id, size, and generation fields.
Consumers fail fast on hard compatibility mismatches and detect stale mappings
when the underlying shm object identity or generation changes.

Future hardening options:

- per-user or per-session shm names,
- tighter owner/group permissions installed by a privileged helper,
- launchd-managed setup that creates the ring before the HAL plug-in opens it,
- XPC-mediated coordination between the app, helper, and driver install path,
- moving more state out of shared memory and into authenticated local IPC.

### Build ID sync check

Before a DAW session, confirm all four build fingerprints agree:

| Artifact | How to read |
|----------|-------------|
| Repo build | `APM44_BUILD_ID` at compile time (CMake prints `APM44 build id:` during configure) |
| Installed helper | `apm44-bridge --version` (`build=` field) |
| Installed driver | `scripts/verify-hal-driver.sh` compares build vs installed HAL executable SHA-256 |
| Live ring | `apm44-bridge --shm-status` → `driver_build_id`, `helper_build_id`, `driver_generation`, `shm_dev`/`shm_ino` |

`helper_build_id` is the daemon binary fingerprint; `driver_build_id` is copied from the HAL producer into the live ring header. When the ring exists, these must match. If they differ, rebuild, reinstall the driver bundle, reload Core Audio (`scripts/reload-coreaudio.sh`), and restart the menu bar app.

## Related

- [Release signing](release.md)
- [Cubase first-run](first-run-cubase.md)
- [verify-hal-driver.sh](../scripts/verify-hal-driver.sh)
