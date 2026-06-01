# Feature Research

**Domain:** macOS HAL virtual audio driver + DAW monitoring bridge — **v1.1 production sign-off**
**Researched:** 2026-06-01
**Confidence:** HIGH (project + Apple/Steinberg docs); MEDIUM (Cubase 15–specific UI labels — verify on host)

## Feature Landscape

v1.0 delivered the **audio engine and HAL skeleton**. v1.1 is not a greenfield feature milestone: it closes **human QA, distribution, and host-integration** gaps so the production path (DAW → **APM44 Bridge** @ 44.1 → shm → daemon → AirPods @ 48) is as credible as the BlackHole MVP path already is in code.

Industry pattern for macOS audio drivers and DAW utilities: **ship signed/notarized binaries**, prove **enumeration in Audio MIDI Setup (AMS)** and at least one reference DAW, run **long listening soaks**, validate **export sample rate ≠ monitoring sample rate**, and document **install/reload** (HAL install → `coreaudiod` kickstart, sometimes reboot). Plugins and loopback tools (Loopback, BlackHole) add routing UX; HAL plug-ins add **trust gates** (Developer ID on macOS 15+).

---

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = v1.1 sign-off fails even if v1.0 code builds.

| Feature | Why Expected | Complexity | Notes / v1.0 dependency |
|---------|--------------|------------|-------------------------|
| **APM44 Bridge** visible in AMS @ **44,100 Hz**, 2ch | Without AMS visibility, DAW cannot select device (DEV-01) | MEDIUM | Depends on `APM44Bridge.driver` installed + **Developer ID signed** load (`DRV-01`); unsigned may fail on macOS 15+ |
| **Cubase 15** lists device under Studio Setup ASIO driver | Primary v1.1 matrix host; replaces Logic/Ableton for operator | MEDIUM | Cubase on Mac uses **CoreAudio2ASIO** — virtual HAL devices appear in the same ASIO driver list as hardware (Steinberg forums, HIGH) |
| Project/session **44.1 kHz** with playback routed to **APM44 Bridge** (DEV-03) | Core product promise | MEDIUM | Requires **DRV-02** (44100-only nominal rates) + correct **Audio Connections** bus mapping |
| **Menu bar** starts daemon with **`--virtual-device`** when HAL installed | End-user path must not require terminal | LOW–MEDIUM | v1.0 gap: app spawns BlackHole path only; needs `App/` + detection of installed driver |
| **30+ min** continuous monitoring on **HAL path** without crackle/drift creep (QA-01 human) | Table stakes for “production monitoring” | HIGH (validation) | Engine exists (`ENG-*`, `apm44-soak`); v1.1 requires soak with **DAW → APM44 Bridge**, not BlackHole-only |
| **Export/bounce @ 44.1 kHz** when project is 44.1 (QA-02) | Producers must trust stems/exports were not silently resampled to 48 | LOW (validation) | `scripts/validate-export-rate.sh` + `afinfo`; monitoring via bridge must not change mixdown SR |
| **Developer ID** signed `.driver`, `.app`, daemon; **notarytool** dry-run on shipping container | Gatekeeper / `coreaudiod` load on modern macOS | MEDIUM | `docs/release.md`; hard gate per PROJECT.md — not documentation-only |
| AirPods Max USB-C remain **48 kHz** in AMS while bridge runs (DEV-04) | Users already validated; must not regress | LOW | Daemon opens AirPods output @ 48; do not force nominal rate on hardware |
| Documented **pre-flight** (`verify-devices.sh`, `apm44-bridge --preflight`) | Support and repeatability | LOW | v1.0 scripts; extend matrix for Cubase |
| **BlackHole fallback** still documented/working | De-risk if HAL blocked | LOW | MVP-01 path; v1.1 adds HAL as primary sign-off, not removal of MVP |

---

### Differentiators (Competitive Advantage)

Not required for “driver loads,” but define why APM44 exists vs generic loopback.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **44.1-only** virtual sink (DRV-02) | Avoids Cubase/AMS rate negotiation picking 48 kHz on a “flexible” virtual device | MEDIUM | Loopback/aggregate expose many rates; APM44 is **opinionated** for DAW @ 44.1 |
| **Purpose-built 44.1→48** drift-aware SRC (`ENG-02`–`04`) | Stable long sessions on fixed 48 kHz USB-C endpoint | HIGH (done) | Loopback monitors to a second device but does not own **clock drift + SRC** for mismatched hardware |
| **Upstream lie** (DAW thinks 44.1, headphones stay 48) | Matches AirPods Max USB-C reality without fighting AMS | LOW (positioning) | Anti-pattern: force 48 kHz project or retune headphones |
| Latency/quality **presets** + fill/glitch meters (`APP-02`–`05`) | Trust for daily monitoring | LOW (done) | Rogue Amoeba has volume/monitor UX; not drift/SRC specialized |
| **HAL + separate daemon** (thin driver, RT in user space) | Aligns with Apple ASPL guidance; AirPods not opened from `.driver` | HIGH (done) | Competitors use user-space virtual devices without custom HAL |
| Honest latency reporting (QA-03) | No “zero latency” marketing | LOW (done) | — |

---

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Aggregate device** (APM44 + AirPods) | Hear mix without separate monitor path | Cubase **single** ASIO device for I/O; aggregate **Core Audio Device Settings** often locked (Steinberg forums, MEDIUM); clock/latency pain | DAW → APM44 only; daemon → AirPods |
| Force **48 kHz project** in Cubase | Match headphones | Breaks 44.1 stems, plug-in assumptions, QA-02 | Keep project @ 44.1; SRC only in bridge |
| **In-driver SRC** to 48 kHz | “One box” | RT risk, malloc, scope creep in `coreaudiod` | Shm + daemon (`DRV-03`) |
| Bundled **BlackHole** in commercial app | Faster onboarding | GPL-3.0 | External install for MVP; own HAL for production |
| **Notarization docs only** without signed HAL load test | Cheaper milestone | macOS 15+ may reject ad-hoc HAL before enumeration (tympan-aspl, Apple notarization docs, HIGH) | Real Developer ID + load on sign-off Mac |
| Logic/Ableton matrix as **v1.1 blocker** | Original v1.0 matrix | Operator has **Cubase 15 only** | Cubase-primary checklist; defer other hosts to v1.2+ |
| **Zero-latency** monitoring claim | Marketing | False for SRC + ring buffer | QA-03 honest numbers |
| Separate Cubase input device ≠ output device | Flexibility | Cubase macOS: one ASIO driver controls both unless aggregate | Use APM44 as **playback** bus; keep inputs on existing interface if needed |

---

## Feature Dependencies

```
Developer ID sign + notarized container (SHIP)
    └──requires──> Signed APM44Bridge.driver loads in coreaudiod
                       └──requires──> AMS shows APM44 Bridge @ 44100 (DEV-01)
                                          └──requires──> DRV-02 (44100-only nominal rates)

Menu bar --virtual-device spawn (APP v1.1)
    └──requires──> apm44-bridge --virtual-device (v1.0 CLI)
    └──requires──> DRV-03 shm ring + driver installed

Cubase routing @ 44100 (DEV-03)
    └──requires──> DEV-01 + DEV-02 + Studio Setup driver selection
    └──requires──> Daemon running (menu bar or CLI) consuming shm

QA-02 export @ 44100
    └──requires──> Cubase project @ 44100 (independent of monitoring SR)
    └──enhances──> DEV-03 (proves monitoring path did not poison export)

30+ min HAL soak (QA-01 human)
    └──requires──> Full chain: Cubase → APM44 → daemon → AirPods
    └──conflicts──> BlackHole-only soak as sole sign-off evidence

BlackHole MVP path
    └──conflicts──> None — parallel fallback; must not block HAL sign-off
```

### Dependency Notes

- **Signing before enumeration:** On macOS 15+, HAL load may fail with ad-hoc signatures (`AppleMobileFileIntegrityError`); AMS/DAW tests are invalid until Developer ID sign passes (community + Apple docs, HIGH).
- **DRV-02 before Cubase rate UI:** If the virtual device advertises 48 kHz, Cubase may switch project or device rate to match (Steinberg Project Setup help, HIGH). **44100-only** list reduces wrong-rate projects.
- **Menu bar `--virtual-device` before producer UX:** v1.0 audit: integration break between Phase 3 app and Phase 4 daemon (`v1.0-MILESTONE-AUDIT.md`).
- **QA-02 is not QA-01:** Export uses **offline mixdown** sample rate; monitoring uses **real-time** 48 kHz on headphones. Pass = file metadata 44100, not “what you heard.”

---

## MVP Definition

### Launch With (v1.1 — Production Sign-Off)

Minimum to close the milestone (maps to PROJECT.md **Current Milestone**):

- [ ] **DEV-01** — AMS shows **APM44 Bridge**, 44.1 kHz, stereo, after signed install + `coreaudiod` reload
- [ ] **DEV-03** — Cubase 15: project 44.1 kHz, playback to **APM44 Bridge**, audible monitoring on AirPods (440 Hz + mix)
- [ ] **DRV-02** — Available nominal sample rates **44100 only** (no 48k/88.2k on virtual device)
- [ ] **APP** — Menu bar spawns **`--virtual-device`** when HAL present; BlackHole path if not
- [ ] **QA-02** — Cubase **Export Audio Mixdown** → WAV/AIFF @ 44100 → `validate-export-rate.sh --check-file` pass
- [ ] **QA-01 (human)** — **30+ min** HAL-path listening soak (documented in `docs/soak-test.md` sign-off table)
- [ ] **SHIP** — Developer ID sign all shipped binaries; **notarytool** dry-run on zip/pkg/dmg; signed HAL loads on sign-off Mac

### Add After Validation (v1.1.x / v1.2)

- [ ] **DAW matrix rows** for Logic, Ableton (scripts exist; operator lacked hosts in v1.1)
- [ ] **Installer/pkg** automation (POL-01) — v1.1 may stay manual `install-driver.sh` if sign-off passes
- [ ] Driver stream **Float32** end-to-end (SInt16 interleaved hardening from v1.0 tech debt)
- [ ] **XPC** daemon control (deferred from v1.0)

### Future Consideration (v2+)

- [ ] **APM44 Bridge Pro** unified engine for Pro Tools (PT-01)
- [ ] Automated latency calibration wizard (POL-02)
- [ ] Bluetooth AirPods path — out of v1 scope

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Signed HAL load + AMS enumeration | HIGH | MEDIUM (certs + process) | **P1** |
| Cubase 15 E2E @ 44.1 → APM44 → AirPods | HIGH | LOW (QA time) | **P1** |
| Menu bar `--virtual-device` wiring | HIGH | LOW | **P1** |
| DRV-02 44100-only rates | HIGH | LOW–MEDIUM | **P1** |
| QA-02 Cubase export + `afinfo` | HIGH | LOW | **P1** |
| 30+ min HAL soak | HIGH | LOW (time) | **P1** |
| Notarytool dry-run | HIGH | MEDIUM | **P1** |
| Cubase-specific doc section in `daw-matrix.md` | MEDIUM | LOW | **P1** |
| Logic/Ableton sign-off | MEDIUM | LOW (deferred) | **P3** |
| Float32 HAL stream hardening | MEDIUM | MEDIUM | **P2** |
| XPC / installer polish | LOW–MEDIUM | HIGH | **P3** |

**Priority key:** P1 = v1.1 milestone done; P2 = soon after; P3 = later milestone.

---

## Cubase 15 — Expected Behavior & Sign-Off Checklist

**Confidence:** HIGH for model (CoreAudio2ASIO, project vs export SR); MEDIUM for Cubase 15 exact menu strings — confirm on installed build.

### How Cubase interacts with macOS audio

| Topic | Expected behavior | Implication for APM44 |
|-------|-------------------|------------------------|
| Driver API on Mac | Cubase presents **ASIO** in Studio Setup; under the hood **CoreAudio2ASIO** wraps Core Audio devices (Steinberg forums, KVR, HIGH) | **APM44 Bridge** must appear as an ASIO driver entry like any Core Audio device |
| Single device default | One ASIO driver typically binds **both** input and output unless using aggregate (forums, MEDIUM) | Route **Stereo Out** to APM44 playback ports; use existing interface for inputs if recording |
| Project sample rate | Set in **Project Setup**; changing later may require converting audio (Steinberg help, HIGH) | Create or confirm project at **44.1 kHz** before long tests |
| Device vs project rate | If project SR is supported by hardware, Cubase may **set device to project rate**; unsupported SR highlighted (Steinberg Project Setup, HIGH) | **DRV-02** ensures device only offers **44100** so negotiation stays on 44.1 |
| Physical headphones | Separate Core Audio device @ **48 kHz** in AMS | **Do not** select AirPods as Cubase ASIO driver for this workflow; monitoring is via bridge daemon |
| Export / mixdown | **Export Audio Mixdown** has explicit **Sample rate** for WAV/AIFF (defaults should match **project** rate; user can override — Steinberg export docs, HIGH) | QA-02: set **44100** (or “project rate”), export, run `validate-export-rate.sh` — proves export ≠ 48 kHz monitoring |

### Cubase 15 sign-off checklist (production / HAL path)

Use alongside `docs/daw-matrix.md` pre-flight. Record pass/fail in sign-off table.

| # | Step | Pass? | Notes |
|---|------|-------|-------|
| 1 | Install **signed** `APM44Bridge.driver`; `verify-hal-driver.sh`; AMS shows **APM44 Bridge** @ **44100 Hz** | | DEV-01 |
| 2 | AMS: **AirPods Max USB-C** @ **48000 Hz** (do not force 44100 on headphones) | | DEV-04 |
| 3 | `verify-devices.sh` + `apm44-bridge --preflight` exit 0 | | |
| 4 | Start bridge: menu bar with **`--virtual-device`** or CLI equivalent; AirPods output UID correct | | APP integration |
| 5 | **Studio → Studio Setup → VST Audio System**: ASIO Driver = **APM44 Bridge** (or exact Core Audio name) | | DEV-03 |
| 6 | **Project → Project Setup**: Sample rate **44100 Hz** | | |
| 7 | **Studio → Audio Connections → Outputs**: **Stereo Out** (or main bus) device ports = **APM44 Bridge** L/R | | |
| 8 | Play **440 Hz** test tone ~10 s: correct pitch in AirPods, no sustained crackle ~2 min | | |
| 9 | **30+ min** continuous playback (loop or mix); no runaway latency / periodic glitches | | QA-01 HAL |
| 10 | **File → Export → Audio Mixdown**: WAV/AIFF, sample rate **44100** / project rate, realtime if required by plugins | | QA-02 |
| 11 | `bash scripts/validate-export-rate.sh --check-file /path/to/export.wav` → exit 0 | | QA-02 |
| 12 | Hotplug: disconnect/reconnect AirPods; bridge recovers without Cubase restart if feasible | | APP-04 |
| 13 | Optional regression: BlackHole MVP path still works per `docs/mvp-routing.md` | | MVP fallback |

### Cubase export (QA-02) — detailed steps

1. Confirm project sample rate **44.1 kHz** (Project Setup).
2. Keep monitoring routed to **APM44 Bridge** with bridge daemon running.
3. **File → Export → Audio Mixdown** (not “real-time offline” unless plugins require **Realtime Export** — Steinberg docs).
4. Format: **WAV** or **AIFF**, **Sample rate: 44100 Hz** (or explicit match to project).
5. Export to known path.
6. Verify: `bash scripts/validate-export-rate.sh --check-file "<path>"`  
   **Pass:** `afinfo` reports 44100 Hz; exit code 0.

**Failure modes to watch:** Export dialog set to **48000** manually; encoder resampling mode that hides sample rate; monitoring device mistaken for “master clock” (export should still follow **project** rate if configured correctly).

---

## Competitor Feature Analysis

| Feature | BlackHole 2ch | Loopback (Rogue Amoeba) | APM44 Bridge v1.1 |
|---------|---------------|-------------------------|-------------------|
| Virtual device in DAW | Yes (loopback sink) | Yes (user-defined virtual device) | Yes (**HAL ASPL**, 44.1-only target) |
| 44.1 → fixed 48 kHz hardware SRC + drift | No (user problem) | No (user wires monitors) | **Yes** (core value) |
| GPL / license for commercial ship | GPL-3.0 (external install OK) | Commercial license | Own driver (MIT libASPL stack) |
| macOS 15+ signed HAL | N/A (third-party) | N/A (user-space) | **Required** for production sign-off |
| DAW export rate honesty | N/A | N/A | **QA-02** explicit validation |
| Multi-app patch bay | No | **Yes** (sources/monitors) | No (single-purpose bridge) |
| Long-session drift control | No | Limited | **ENG-04** ±500 ppm |

---

## Sources

| Source | Confidence | Used for |
|--------|------------|----------|
| `.planning/PROJECT.md`, `milestones/v1.0-MILESTONE-AUDIT.md` | HIGH | v1.1 scope, gaps, dependencies |
| `docs/daw-matrix.md`, `docs/soak-test.md`, `docs/hal-driver.md`, `docs/release.md` | HIGH | QA procedures, HAL path |
| `scripts/validate-export-rate.sh` | HIGH | QA-02 contract |
| [Steinberg — Project Setup (sample rate)](https://archive.steinberg.help/cubase_pro/v10.5/en/cubase_nuendo/topics/project_handling/project_handling_project_setup_dialog_r.html) | HIGH | Project vs device rate |
| [Steinberg — Export Audio Mixdown (sample rate)](https://steinberg.help/cubase_pro/v11/en/cubase_nuendo/topics/export_audio_mixdown/export_audio_mixdown_options_r.html) | HIGH | QA-02 export behavior |
| [Steinberg Forums — CoreAudio2ASIO on Mac](https://forums.steinberg.net/t/cubase-on-mac-confused-about-asio-vs-core-audio/621691) | HIGH | Cubase driver model |
| [Apple — Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | HIGH | Plug-in notarization expectations |
| [tympan-aspl — HAL signing on macOS 15](https://github.com/penta2himajin/tympan-aspl) | MEDIUM | Ad-hoc vs Developer ID load |
| [Rogue Amoeba — Loopback](https://rogueamoeba.com/loopback/) | MEDIUM | Competitor monitoring UX |
| [NI — Configure audio interface in Cubase](https://support.native-instruments.com/hc/en-us/articles/210312585-How-to-Configure-an-Audio-Interface-in-Cubase) | MEDIUM | Studio Setup / Audio Connections flow |

---
*Feature research for: APM44 Bridge v1.1 production sign-off*
*Researched: 2026-06-01*
