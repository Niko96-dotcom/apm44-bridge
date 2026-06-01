# Cubase 15 HAL soak test (QA-01)

Human-only validation for **Cubase 15 → APM44 Bridge (HAL) → apm44-bridge → AirPods Max USB-C @ 48 kHz**.

> **Operator:** Complete this checklist on the sign-off Mac. The agent cannot run Cubase.

## Prerequisites

- [ ] Signed, stapled `APM44Bridge.driver` installed (`scripts/verify-hal-driver.sh` passes Gatekeeper)
- [ ] **APM44 Bridge** menu bar app running (HAL routing mode shown)
- [ ] Cubase 15 project @ **44,100 Hz**
- [ ] Control Room Monitor 1 L/R → **APM44 Bridge** (see [first-run-cubase.md](first-run-cubase.md))
- [ ] AirPods Max **USB-C** @ **48,000 Hz** in Audio MIDI Setup

## Soak procedure (30+ minutes)

| Step | Time | Pass? | Notes |
|------|------|-------|-------|
| Start bridge from menu bar; status reaches **Running** | 0–2 min | | |
| Play looped mix or 440 Hz tone | | | |
| Confirm AirPods still **48,000 Hz** in AMS (DEV-04) | 5 min | | |
| Continuous playback, no crackle | 30 min | | |
| Menu bar glitch counter stable (no runaway xruns) | 30 min | | |
| Stop bridge; note final metrics in stderr log if needed | end | | |

## Regression checks

| Check | Expected | Pass? |
|-------|----------|-------|
| Export mixdown @ project rate | **44,100 Hz** file (`validate-export-rate.sh`) | |
| Hotplug: disconnect/reconnect USB | Bridge recovers without Cubase restart | |
| HAL path (not BlackHole) | Menu bar shows **APM44 Bridge (driver)** | |

## Evidence to capture

```
Date:
macOS version:
Cubase version (15.x):
Bridge build/commit:
Soak duration (minutes):
Peak fill_ms (from menu bar):
Final xruns:
DEV-04 AirPods @ 48 kHz during soak: pass/fail
QA-02 export @ 44100: pass/fail
Overall: pass/fail
```

## Automated helpers (before/after soak)

```bash
bash scripts/verify-hal-driver.sh
bash scripts/verify-devices.sh
bash scripts/validate-export-rate.sh --check-file /path/to/export.wav
```

Full matrix: [daw-matrix.md](daw-matrix.md)
