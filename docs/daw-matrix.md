# DAW validation matrix

End-to-end checklist for **Cubase 15** (v1.1 primary sign-off), plus **Logic Pro** and **Ableton Live** (deferred beyond v1.1). Record **pass** / **fail** / **skip** in the right column after each run.

## Signal paths

| Mode | DAW output | Bridge input | Notes |
|------|------------|--------------|-------|
| **MVP (now)** | BlackHole 2ch @ 44100 Hz | `apm44-bridge` HAL input | Phase 1–3 stack; user installs BlackHole (GPL, not bundled) |
| **Production (Phase 4+)** | **APM44 Bridge** @ 44100 Hz | `apm44-bridge --virtual-device` | HAL plug-in; no BlackHole required |

Monitoring path in both cases: bridge resamples **44100 → 48000** and plays to **AirPods Max USB-C @ 48000 Hz**. The DAW project rate stays **44100 Hz**.

## Pre-flight (all hosts)

| Step | Pass? | Notes |
|------|-------|-------|
| macOS 14+ | | |
| BlackHole 2ch @ **44100 Hz** (MVP) or **APM44 Bridge** @ **44100 Hz** (production) in Audio MIDI Setup | | |
| AirPods Max USB-C @ **48000 Hz** (do **not** force 44100 on headphones) | | |
| `bash scripts/verify-devices.sh` → exit 0 | | |
| `./build/BridgeDaemon/apm44-bridge --preflight` → exit 0 | | |
| Menu bar app **APM44 Bridge** running (or CLI bridge started) | | |

| **Production (Phase 4+)** | **APM44 Bridge** @ 44100 Hz | `apm44-bridge --virtual-device` | HAL plug-in; menu bar spawns automatically when driver detected |

## Cubase 15 (v1.1 sign-off host)

| Step | Production (APM44 Bridge HAL) | Pass? | Notes |
|------|-------------------------------|-------|-------|
| Project sample rate **44100 Hz** | ✓ | | |
| VST Audio System output **APM44 Bridge** | ✓ | | |
| Control Room Monitor 1 **L/R device ports** → APM44 Bridge | ✓ | | See [first-run-cubase.md](first-run-cubase.md) |
| Menu bar routing **APM44 Bridge (driver)** | ✓ | | Not BlackHole fallback |
| Play 440 Hz ~10 s; audible in AirPods USB | ✓ | | |
| AirPods Max USB-C stays **48000 Hz** in AMS (DEV-04) | ✓ | | |
| **30+ min** soak (see [cubase-soak.md](cubase-soak.md)) | ✓ | | QA-01 |
| Audio Mixdown export **44100 Hz** (QA-02) | ✓ | | `validate-export-rate.sh` |

### Cubase export (QA-02)

1. **File → Export → Audio Mixdown**
2. Sample rate: **44,100 Hz**
3. Export WAV
4. `bash scripts/validate-export-rate.sh --check-file /path/to/mix.wav`

## Logic Pro

| Step | MVP (BlackHole) | Production (APM44 Bridge) | Pass? |
|------|-----------------|---------------------------|-------|
| Project / session sample rate **44100 Hz** | ✓ | ✓ | |
| Output device **BlackHole 2ch** | ✓ | — | |
| Output device **APM44 Bridge** | — | ✓ | |
| Play **440 Hz** test tone ~10 s; audible in AirPods, correct pitch | ✓ | ✓ | |
| Buffer size stable (e.g. 512); no sustained crackle ~2 min | ✓ | ✓ | |
| **30+ min** continuous playback (see [soak-test.md](soak-test.md)) | ✓ | ✓ | |
| Bounce / export stereo mix @ project rate; file is **44100 Hz** (QA-02) | ✓ | ✓ | |
| Hotplug: disconnect/reconnect AirPods; bridge recovers without DAW restart | ✓ | ✓ | |

### Logic bounce (QA-02)

1. **File → Bounce → Project or Section**
2. Sample rate: **Use project sample rate** (44100)
3. Export WAV or AIFF
4. Verify: `bash scripts/validate-export-rate.sh --check-file /path/to/bounce.wav`

## Ableton Live

| Step | MVP (BlackHole) | Production (APM44 Bridge) | Pass? |
|------|-----------------|---------------------------|-------|
| Preferences → Audio → Sample rate **44100 Hz** | ✓ | ✓ | |
| Audio Output Device **BlackHole 2ch** | ✓ | — | |
| Audio Output Device **APM44 Bridge** | — | ✓ | |
| Play **440 Hz** tone ~10 s; audible in AirPods, correct pitch | ✓ | ✓ | |
| No sustained crackle ~2 min under normal CPU load | ✓ | ✓ | |
| **30+ min** continuous playback (see [soak-test.md](soak-test.md)) | ✓ | ✓ | |
| Export audio; file is **44100 Hz** (QA-02) | ✓ | ✓ | |
| Hotplug recovery (menu bar app) | ✓ | ✓ | |

### Ableton export (QA-02)

1. Select time range; **File → Export Audio/Video**
2. Sample rate: **44100 Hz** (match project)
3. Export WAV
4. Verify: `bash scripts/validate-export-rate.sh --check-file /path/to/export.wav`

## Sign-off record

| Field | Value |
|-------|-------|
| Date | |
| Tester | |
| macOS version | |
| Cubase version | |
| Logic version | |
| Ableton version | |
| Bridge commit / build | |
| MVP path result | pass / fail |
| Production path result | pass / fail / pending Phase 4 |
| QA-02 export check | pass / fail |
| QA-01 30+ min soak | pass / fail (link notes) |

## Automated gates (CI / local)

These do **not** replace the hardware matrix above:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
bash scripts/ci-soak.sh          # offline soak
bash scripts/verify-menu-bar.sh  # app + metrics tests
bash scripts/validate-export-rate.sh --instructions
```

## Related docs

- [MVP routing (BlackHole)](mvp-routing.md)
- [Soak test (QA-01)](soak-test.md)
- [Menu bar hardware QA](menu-bar-qa.md)
- [Release signing](release.md)
