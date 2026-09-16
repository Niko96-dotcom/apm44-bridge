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
| Menu bar extra is a template image (follows menu-bar tint) | |
| Status shows Running / Stopped | |
| Running uses a waveform glyph; stopped uses headphones | |
| Output picker shows a name, “Choose output…”, or “Unavailable” — never a blank closed value | |
| Start / Stop / Restart / Quit have unique names | |
| Start is bordered (not prominent fill) when disabled, with the reason next to it | |

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
| Running label identifies `~N ms bridge buffering` with N > 0 | |
| Copy states device, DAW, and hardware latency are additional | |
| No "zero latency" copy anywhere | |
| Driver / converter counters stay inside **Details** | |

## APP-06 — First run, help, and language

| Step | Pass? |
|------|-------|
| Incomplete setup offers **Skip Setup**, not Continue/Done | |
| Footer **Setup** reopens the sheet after skip | |
| **Cubase setup guide** is a named control | |
| German system language shows German chrome (Start, Ausgabe, Beenden) | |
| Open at login is a regular checkbox, not a switch | |

## Automated gate

```bash
bash scripts/verify-menu-bar.sh
```

**Sign-off:** Type `approved` when all rows pass, or list failing step numbers.
