# Cubase 15 first-run setup

Guide for **Cubase 15** (German UI supported) with the **APM44 Bridge** HAL path. No Terminal required after installing the release DMG.

## Before Cubase

1. Install **APM44 Bridge** from the release DMG.
2. Open **APM44 Bridge** from the menu bar — complete the first-run preflight sheet.
3. In **Audio MIDI Setup**:
   - **APM44 Bridge** → **44,100 Hz** (only rate offered after Phase 7 hardening)
   - **AirPods Max USB-C** → **48,000 Hz** (do not force 44.1 on headphones)
4. Start bridge from the menu bar (daemon uses `--virtual-device` when HAL is detected).

## Cubase project

| Setting | Value |
|---------|-------|
| Project sample rate | **44,100 Hz** |
| Audio output (VST Audio System) | **APM44 Bridge** |

## Control Room — device ports (critical)

Cubase routes monitoring through **Control Room**. You must assign **APM44 Bridge** to the monitor outputs:

### English UI

1. **Studio → Control Room** (enable if prompted).
2. Open **Control Room** panel.
3. Under **Monitor 1** (or your active monitor), set **Device Port**:
   - **Left** → **APM44 Bridge** (first channel)
   - **Right** → **APM44 Bridge** (second channel)

### German UI (Cubase 15)

1. **Studio → Control Room** aktivieren.
2. Im **Control Room**-Fenster unter **Monitor 1**:
   - **Geräteanschluss Links** → **APM44 Bridge**
   - **Geräteanschluss Rechts** → **APM44 Bridge**

Without L/R port assignment, Cubase may play to the wrong device or you hear silence while the bridge shows **Waiting for DAW**.

## Verify monitoring

1. Create a **440 Hz** test tone on an audio track.
2. Press Play — menu bar should progress: **Waiting for DAW** → **Connected** → **Running**.
3. Confirm audio in AirPods (USB-C, not Bluetooth-only).

## Export @ 44.1 kHz (QA-02)

1. **File → Export → Audio Mixdown**
2. Sample rate: **44,100 Hz** (project rate)
3. Export WAV to Desktop
4. Verify:

```bash
bash scripts/validate-export-rate.sh --check-file ~/Desktop/your-mix.wav
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No sound, bridge **Waiting for DAW** | Control Room L/R ports → APM44 Bridge |
| Bridge uses BlackHole | Install HAL driver; check preflight sheet |
| Crackle / xruns | Increase latency preset in menu bar (Balanced → Safe) |
| APM44 missing in AMS | Reinstall driver; reboot once after first HAL install |

See also: [daw-matrix.md](daw-matrix.md), [soak-test.md](soak-test.md), [hal-driver.md](hal-driver.md).
