# MVP routing: DAW → BlackHole → apm44-bridge → AirPods

Phase 1 proves the sample-rate bridge without a custom HAL driver or menu bar app.

## Signal path

```
DAW @ 44.1 kHz (project rate)
    ↓  stereo output
BlackHole 2ch @ 44.1 kHz  (virtual loopback)
    ↓  Core Audio input IOProc
apm44-bridge (libsamplerate SRC 44.1 kHz -> 48 kHz)
    ↓  Core Audio output IOProc
AirPods Max USB-C @ 48 kHz  (physical headphones)
```

ASCII overview:

```
+-------------+     +------------------+     +---------------+     +------------------+
| Logic /     |     | BlackHole 2ch    |     | apm44-bridge  |     | AirPods Max      |
| Ableton     | --> | @ 44100 Hz       | --> | resample 48k  | --> | USB-C @ 48000 Hz |
| @ 44100     |     | (user-installed) |     | (this repo)   |     |                  |
+-------------+     +------------------+     +---------------+     +------------------+
```

## Before you start

1. Install BlackHole — see [blackhole-prerequisite.md](blackhole-prerequisite.md).
2. Connect **AirPods Max USB-C** (or pass `--output-device` with another 48 kHz output UID).
3. Set rates in **Audio MIDI Setup**:
   - BlackHole 2ch → **44100 Hz**
   - AirPods Max USB-C → **48000 Hz** (do **not** force 44100 on AirPods)
4. Run preflight:

```bash
bash scripts/verify-devices.sh
cmake -S . -B build && cmake --build build
./build/BridgeDaemon/apm44-bridge --preflight
```

Exit code 0 means devices and nominal rates look correct.

## Build and run the bridge

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/BridgeDaemon/apm44-bridge
```

Optional overrides:

```bash
./build/BridgeDaemon/apm44-bridge --input-device "<BlackHole UID>"
./build/BridgeDaemon/apm44-bridge --output-device "<AirPods UID>"
./build/BridgeDaemon/apm44-bridge --print-config   # resolved UIDs/rates without audio
./build/BridgeDaemon/apm44-bridge --list-devices   # full device table
```

On start, the bridge prints **actual HAL buffer frame sizes** for input and output. MVP targets 512 frames at 44.1 kHz where the driver allows it; if `AudioDeviceSetProperty` fails, the logged device default is used.

Leave the bridge running while the DAW plays. Stop with **Ctrl+C**; stderr prints an **xrun** counter (underruns / conversion failures).

## Logic Pro

1. **Logic Pro → Settings → Audio** (or Project Settings → Audio).
2. Set sample rate / project rate to **44.1 kHz**.
3. Set **Output Device** to **BlackHole 2ch** (not AirPods — the bridge owns AirPods).
4. Start `apm44-bridge` in Terminal.
5. Create a test tone: **Track → New Tracks → Software Instrument** or use the test oscillator / tone plug-in at **440 Hz**.
6. Play for ~10 seconds. You should hear the tone in AirPods.

## Ableton Live

1. **Preferences → Audio** (macOS).
2. Audio Output Device: **BlackHole 2ch**.
3. Sample Rate: **44100 Hz**.
4. Start `apm44-bridge`.
5. Add a test tone (e.g. Operator sine at **440 Hz**) on a track and play.

## Success demo (Phase 1)

| Step | Action |
|------|--------|
| 1 | `bash scripts/verify-devices.sh` → PASS both lines |
| 2 | Confirm rates in Audio MIDI Setup (44100 / 48000) |
| 3 | Run `./build/BridgeDaemon/apm44-bridge` |
| 4 | DAW → BlackHole @ 44100, play **440 Hz** tone ~10 s |
| 5 | Hear tone in AirPods; pitch should be correct (not half/double speed) |
| 6 | Ctrl+C bridge; note xrun count |

Human verification is required for step 5 in environments with real hardware.

## Troubleshooting

### Silence

- Run `--preflight` and `verify-devices.sh`.
- Confirm DAW output is **BlackHole**, not AirPods or built-in speakers.
- Confirm bridge is running and not exiting with an error.
- Check macOS output volume / AirPods connection.

### Wrong pitch (chipmunk / slow)

- Almost always a **sample rate mismatch**: BlackHole must be **44100**, AirPods **48000**.
- Re-check Audio MIDI Setup; do not set AirPods to 44100.

### Crackle / dropouts (MVP)

- Expected occasionally under load; Phase 1 has **no drift control** and minimal buffering.
- Note xrun count on exit; reduce DAW buffer if needed.

### High latency

- MVP adds ring buffer + SRC delay by design; no Low/Balanced/Safe presets until later phases.

## Related scripts

- `scripts/verify-devices.sh` — machine-readable `--json` flag for automation
- `apm44-bridge --preflight` — same rate policy inside the binary

## What Phase 1 does not include

- Custom **APM44 Bridge** HAL device (Phase 4)
- **libsamplerate** drift engine (Phase 2)
- Menu bar app / latency presets (Phase 3)
- LaunchAgent auto-start
