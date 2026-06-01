# Milestones

## v1.1 Production Sign-Off (In progress: 2026-06-01)

**Goal:** Close v1.0 audit gaps — signed HAL, Cubase 15 E2E, app `--virtual-device` wiring, DRV-02, 30+ min HAL soak, export QA.

**Phases:** 6–9 (4 phases, 11 requirements)

**Roadmap:** [.planning/ROADMAP.md](ROADMAP.md) · **Requirements:** [.planning/REQUIREMENTS.md](REQUIREMENTS.md)

---

## v1.0 APM44 Bridge MVP (Shipped: 2026-06-01)

**Phases completed:** 5 phases, 23 plans, 3 tasks

**Key accomplishments:**

- CMake 3.28 monorepo with Shared ASBD helpers, Catch2 unit tests, and apm44-bridge CLI parsing --help/--version/device UIDs.
- HAL enumeration with UID listing, BlackHole/AirPods defaults, format verification, and shell preflight script.
- Dual HAL IOProcs with lock-free planar ring and persistent AudioConverter; RT handlers contain no logging.
- MVP routing guide for Logic/Ableton, BlackHole GPL prerequisite doc, and verification matrix marking 440 Hz demo as human_needed.
- Static libsamplerate 0.2.2 integrated into CMake with an offline `src_process` smoke test.
- Planar ring buffer upgraded to power-of-two SPSC with fill frame/ms helpers at 44.1 kHz.
- PI drift controller maps ring fill error to bounded ppm adjustment on nominal 48000/44100 SRC ratio.
- RT-safe libsamplerate wrapper with variable `src_ratio` and quality presets for bridge output path.
- Default bridge path uses libsamplerate + drift PI; CLI exposes fill target, SRC quality, and legacy converter.
- Offline clock-skew soak (`apm44-soak`) validates drift+SRC stability; human 30+ min procedure documented.
- SwiftUI menu bar app spawns `apm44-bridge` with running/stopped/error icon states and Start/Stop control.
- Daemon emits single-line JSON metrics every 500 ms on stdout when `--metrics-json` is set, with `estimated_rt_ms = fill_ms + SRC group delay`.
- Menu parses daemon JSON lines and shows buffer fill, glitch indicator, and `~N ms monitoring latency` copy.
- Output picker lists `apm44-bridge --list-devices` outputs and passes `--output-device` on start.
- Menu exposes Low/Balanced/Safe target fill and Standard/High/Best SRC tier mapped to daemon CLI flags.
- Core Audio device-list listener debounces 1 s and restarts the bridge if it was running when outputs change.
- Phase 3 CI gate runs app build, C++/Swift tests, and copy invariants; hardware UAT checklist documents APP/QA sign-off.
- libASPL v3.1.2 vendored and wired into root CMake for the HAL driver target.
- Cross-process SPSC ring in POSIX shm (`/apm44_bridge_ring`) with Catch2 coverage.
- `APM44Bridge.driver` builds: libASPL virtual output device pushing DAW audio into shm.
- `apm44-bridge --virtual-device` consumes shm in the output IOProc path (no BlackHole input client).
- Dev install scripts and HAL documentation; phase verification records honest manual gaps.
- DAW validation matrix, QA-02 export-rate script, and Developer ID / notarytool release guide with HAL entitlements.

**Audit:** `gaps_found` at close (17/23 requirements fully evidenced; accepted — see Known Gaps below).

### Known Gaps (accepted at ship)

| ID | Gap |
|----|-----|
| DEV-01 | HAL driver builds; AMS/DAW enumeration needs signed install + manual QA |
| DEV-03 | DAW @ 44.1 → APM44 Bridge not verified end-to-end |
| DRV-02 | 44100 Hz set; exclusive nominal-rate list not hardened |
| QA-02 | `validate-export-rate.sh` ready; Logic/Ableton bounce not run |
| Integration | Menu bar does not pass `--virtual-device` to daemon |
| Ship | Developer ID / notarization dry-run not executed |

**Archives:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) · [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md)

---
