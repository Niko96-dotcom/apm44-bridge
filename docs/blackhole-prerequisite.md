# BlackHole prerequisite (legacy fallback)

APM44 Bridge now uses its own HAL driver for the normal production path. The
older BlackHole route remains documented as a developer fallback. BlackHole is
a separate product; we do not bundle, vendor, or statically link it.

## Install

1. Download **BlackHole 2ch** v0.6.1 or newer from the official release page:  
   https://github.com/ExistentialAudio/BlackHole/releases
2. Run the installer package and approve the system extension / driver prompts if macOS asks.
3. Reboot if the installer instructs you to (first install on some macOS versions).

## GPL-3.0 notice

BlackHole is licensed under **GPL-3.0**. APM44 Bridge:

- Does **not** ship BlackHole inside the app or repository
- Does **not** fork or statically link BlackHole
- Expects you to install BlackHole yourself for the fallback routing path

If you distribute a commercial product that bundles BlackHole, you need a separate license from Existential Audio (see their README).

## Audio MIDI Setup

1. Open **Audio MIDI Setup** (Applications → Utilities).
2. Select **BlackHole 2ch** in the sidebar.
3. Set the format / sample rate to **44,100 Hz** (44.1 kHz).
4. Confirm **2 channels** and that the device is enabled.

<!-- screenshot: docs/images/blackhole-44100.png — BlackHole 2ch format pane showing 44100 Hz -->

Checklist:

- [ ] BlackHole 2ch appears in Audio MIDI Setup
- [ ] Nominal sample rate is **44100 Hz**
- [ ] Device is not muted / disabled

## Verify from terminal

```bash
bash scripts/verify-devices.sh
./build/BridgeDaemon/apm44-bridge --preflight
```

Both should report success when BlackHole is installed at 44.1 kHz.
