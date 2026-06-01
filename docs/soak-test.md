# Soak test (QA-01)

Long-session stability validation for the production SRC + drift path (libsamplerate, ring fill controller, ±500 ppm drift).

## Prerequisites

- macOS 14+
- **BlackHole 2ch** v0.6.1+ installed (user-provided, GPL-3.0 — not bundled)
- BlackHole set to **44100 Hz** in Audio MIDI Setup
- **AirPods Max USB-C** connected at **48000 Hz** (do not force 44100 on the headphones)
- Built binaries: `apm44-bridge`, `apm44-soak`

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Automated offline soak (CI / quick check)

No DAW or HAL devices required:

```bash
./build/BridgeDaemon/apm44-soak --duration-sec 60
# Quick smoke:
./build/BridgeDaemon/apm44-soak --duration-sec 30
```

Or run the CI script:

```bash
bash scripts/ci-soak.sh
```

**Pass criteria (offline):** exit code 0; `passed=1` in stdout; underruns below threshold; fill does not exceed 2× target for more than 1 s.

## Human 30+ minute soak (full QA-01)

1. Run `bash scripts/verify-devices.sh` — both input (BlackHole @ 44100) and output (AirPods @ 48000) should PASS.
2. `./build/BridgeDaemon/apm44-bridge --preflight` — exit 0.
3. Start the bridge with recommended flags:

   ```bash
   ./build/BridgeDaemon/apm44-bridge \
     --target-fill-ms 15 \
     --src-quality medium
   ```

4. Route audio into BlackHole:
   - **DAW:** Logic or Ableton — project rate **44100 Hz**, output **BlackHole 2ch**, loop a mix or 440 Hz tone.
   - **Quick loop:** `afplay` on a file routed via Multi-Output or DAW (BlackHole must receive the 44.1 kHz stream).

5. Listen on AirPods for **at least 30 minutes**.

### Pass criteria (listening)

- No crackle, dropouts, or runaway latency (pitch does not slowly drift audibly).
- On Ctrl+C, bridge prints fill_ms, ratio, ppm, underruns, overruns, xruns — counts should not climb steadily.

### Record for sign-off

| Field | Value |
|-------|--------|
| Date | |
| macOS version | |
| Buffer sizes (from bridge startup log) | |
| `--target-fill-ms` | |
| `--src-quality` | |
| Notes (glitches, xruns) | |

## Debug: legacy AudioToolbox converter

Compare against Phase 1 path:

```bash
./build/BridgeDaemon/apm44-bridge --legacy-converter
```
