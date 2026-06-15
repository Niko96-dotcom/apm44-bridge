# Menu bar hardware QA checklist

Map each step to requirements and record pass/fail in the release or QA notes.

## Setup

1. Signed, notarized APM44 Bridge DMG installed.
2. **APM44 Bridge** nominal rate **44100 Hz** in Audio MIDI Setup.
3. AirPods Max USB-C connected; nominal rate **48000 Hz**.
4. Run **APM44 Bridge** from `/Applications`.
5. For developer builds only, set `APM44_BRIDGE_PATH="$PWD/build/BridgeDaemon/apm44-bridge"` and open the Debug app.

## APP-01 — Menu bar control

| Step | Pass? |
|------|-------|
| Menu bar icon appears (headphones) | |
| Status shows Running / Stopped | |
| Output picker shows device name | |
| Start / Stop toggles bridge | |
| Icon tint: gray stopped, green running, red on error | |

## APP-02 — Latency presets

| Step | Pass? |
|------|-------|
| Low / Balanced / Safe selectable | |
| Safe default on fresh install | |
| Each preset restarts bridge when changed while running | |

## APP-03 — SRC quality

| Step | Pass? |
|------|-------|
| Standard / High / Best picker works; each label maps to distinct SRC behavior | |
| Safe preset defaults to Best until overridden | |

## APP-04 — Hotplug

| Step | Pass? |
|------|-------|
| With bridge running, disconnect AirPods ≥2 s | |
| Reconnect; within ~2 s after debounce bridge auto-restarts | |
| DAW session continues without DAW restart | |

## APP-05 — Meters

| Step | Pass? |
|------|-------|
| Buffer fill bar moves while audio plays | |
| Glitch indicator when xruns increase | |

## QA-03 — Honest latency

| Step | Pass? |
|------|-------|
| Running label shows `~N ms monitoring latency` with N > 0 | |
| No "zero latency" copy anywhere | |

## Automated gate

```bash
bash scripts/verify-menu-bar.sh
```

**Sign-off:** Type `approved` when all rows pass, or list failing step numbers.
