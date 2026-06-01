# Project Research Summary

**Project:** APM44 Bridge v1.1 Production Sign-Off
**Domain:** macOS HAL virtual audio driver + DAW monitoring bridge (44.1 kHz DAW → 48 kHz AirPods Max USB-C)
**Researched:** 2026-06-01
**Confidence:** HIGH

## Executive Summary

APM44 Bridge v1.1 is an **integration and distribution milestone**, not a greenfield audio build. v1.0 already ships the RT engine (libsamplerate, drift control, shm ring, dual CLI paths for BlackHole vs `--virtual-device`). v1.1 closes the gap between that engine and **production credibility**: Developer ID–signed HAL load on macOS 15+, menu bar that spawns the correct daemon mode, driver nominal-rate hardening (44100-only), and **human sign-off** on Cubase 15 with export-rate validation and a 30+ minute HAL-path soak.

Experts ship macOS audio drivers as **signed Audio Server Plug-ins** installed under `/Library/Audio/Plug-Ins/HAL/`, with hardened-runtime `codesign`, notarized **containers** (zip/dmg/pkg—not loose `.driver`), and host QA in Audio MIDI Setup plus at least one reference DAW. APM44 follows that pattern: thin HAL in `coreaudiod`, all SRC and AirPods I/O in the user-space daemon, app as non-RT control plane only.

The recommended v1.1 approach is **sign first, then enumerate, then wire app, then soak**. Ad-hoc HAL signing and Cubase matrix runs on unsigned builds produce false negatives (AMFI rejection before plug-in code runs). Parallel work on DRV-02 and app wiring is fine on dev machines, but **milestone complete** requires all three on a sign-off Mac with Cubase 15. BlackHole MVP remains documented fallback; v1.1 does not remove it.

Key risks: (1) treating notarized app as sufficient while HAL stays unsigned; (2) menu bar spawning BlackHole path while DAW routes to APM44; (3) DRV-02 implemented as default rate only without `SetAvailableSampleRatesAsync`; (4) Cubase routing/export mistakes masquerading as bridge bugs; (5) hidden SInt16 HAL vs float32 shm format debt during listen tests. Mitigation is explicit phase gates, property probes, argv verification, and a Cubase-first checklist in `docs/daw-matrix.md`.

## Key Findings

### Recommended Stack

v1.1 adds **no new audio or SRC dependencies**. Baseline unchanged: macOS 14+, Xcode 16, C++20 daemon, SwiftUI menu bar, libASPL **v3.1.2**, libsamplerate **0.2.2**, POSIX shm SPSC, CMake 3.28+.

**v1.1 stack additions** center on Apple distribution and HAL contract tightening:

**Core technologies:**
- **Apple Developer Program + Developer ID Application:** Issue certs for `.driver`, `apm44-bridge`, and `APM44 Bridge.app` — macOS 15+ often rejects ad-hoc HAL before enumeration (hard gate).
- **`codesign` + Hardened Runtime (`--options runtime`):** Sign inner Mach-O then bundle; empty driver entitlements (no App Sandbox on HAL).
- **`xcrun notarytool` + `xcrun stapler`:** Submit zip/dmg/pkg; staple user-facing `.app`; replace deprecated `altool`.
- **libASPL `SetAvailableSampleRatesAsync({44100, 44100})`:** DRV-02 — exclusive 44100 nominal list, not default rate only.
- **Cubase Pro 15.x:** Primary sign-off host via Core Audio (CoreAudio2ASIO); no Steinberg SDK required.

**Supporting tooling:** `security find-identity`, `notarytool store-credentials`, `codesign --verify --deep --strict`, `spctl`, `ditto -c -k`, extended `verify-hal-driver.sh` / `verify-devices.sh` / `validate-export-rate.sh`, optional `scripts/sign-release.sh` and CMake `CODESIGN_ID` post-build.

See [STACK.md](./STACK.md) for signing order, CI split (build-test vs sign-notarize workflow_dispatch), and Cubase routing table.

### Expected Features

v1.1 delivers **trust and host integration**, not new DSP.

**Must have (table stakes):**
- **APM44 Bridge in AMS @ 44.1 kHz, 2ch** after signed install + `coreaudiod` reload (DEV-01).
- **Cubase 15** lists device; project @ 44100; playback to APM44 Bridge; monitoring on AirPods via daemon (DEV-03).
- **Menu bar spawns `--virtual-device`** when HAL present; BlackHole fallback when not (APP).
- **DRV-02** — available nominal sample rates **44100 only**.
- **QA-02** — Cubase export/bounce @ 44100 verified with `validate-export-rate.sh` + `afinfo`.
- **QA-01 (human)** — 30+ min continuous monitoring on **HAL path** (not BlackHole-only soak).
- **SHIP** — Developer ID on all shipped binaries; `notarytool` dry-run; signed HAL loads on sign-off Mac.
- **AirPods remain @ 48 kHz** in AMS while bridge runs (DEV-04).
- **BlackHole fallback** still documented (MVP-01).

**Should have (differentiators — largely done in v1.0):**
- Purpose-built 44.1→48 drift-aware SRC; upstream “lie” at 44100; latency presets and honest metrics.

**Defer (v1.1.x / v1.2+):**
- Logic/Ableton matrix rows (operator has Cubase only).
- Installer/pkg automation, XPC, Float32 HAL stream end-to-end hardening as non-blocker if listen tests pass.
- Pro Tools unified engine, Bluetooth path (v2+).

See [FEATURES.md](./FEATURES.md) for dependency graph and Cubase 15 sign-off checklist (13 steps).

### Architecture Approach

v1.1 **does not change the audio graph** — it closes control-plane and release-plane gaps. Single `BridgeEngine` with dual input: HAL shm (`--virtual-device`) or BlackHole input IOProc. Menu bar adds `HalRoutingPolicy` to detect `com.niko.apm44.bridge.device` @ ~44100 and append `--virtual-device`. Signing/install is a prerequisite plane parallel to runtime.

**Major components:**
1. **`APM44Bridge.driver`** — Virtual output @ 44100; DAW PCM → shm; never opens AirPods. **Modify:** DRV-02 rate list.
2. **`apm44-bridge`** — SRC, drift, output @ 48 kHz. **Unchanged**; `--virtual-device` already implemented.
3. **`APM44 Bridge.app`** — Spawn daemon, metrics, device picker. **Modify:** routing mode + CLI args.
4. **Release/QA plane** — codesign → HAL install → kickstart → AMS/Cubase matrix → soak → export validation.

**Build order (opinionated):** (1) Signing pipeline → (2) DRV-02 → (3) App wiring (logic can start unsigned; sign-off needs signed HAL) → (4) Human QA. Do **not** block signing on app; do **not** mark Cubase matrix done on ad-hoc HAL.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for diagrams and anti-patterns (signing after DAW QA, app mmap shm, removing BlackHole path).

### Critical Pitfalls

1. **Ad-hoc HAL on macOS 15+** — Device never enumerates; AMFI errors in Console. Use Developer ID Application, verify with `codesign --verify --deep --strict`, install to system HAL path, kickstart `coreaudiod`, reboot if needed.

2. **Notarized app ≠ loadable HAL** — Gatekeeper happy, `coreaudiod` still refuses unsigned driver. Separate acceptance tests; notarize signed driver zip and/or pkg; staple distributable artifact, not upload zip.

3. **Menu bar without `--virtual-device`** — Cubase → APM44 but daemon on BlackHole → silence/wrong path. Centralize `BridgeLaunchProfile`; verify spawn argv in QA.

4. **DRV-02 as default rate only** — AMS/Cubase may offer or switch to 48 kHz. Call `SetAvailableSampleRatesAsync({44100,44100})`; reject other nominal rates.

5. **Cubase checklist errors** — Wrong ASIO driver, export @ 48 kHz, AirPods forced to 44100, “Release driver in background.” Cubase-primary matrix; DAW → APM44 only; AirPods via daemon @ 48 kHz.

See [PITFALLS.md](./PITFALLS.md) for notarization container mistakes, SInt16/float format debt, hotplug lifecycle, and “looks done but isn’t” checklist.

## Implications for Roadmap

Based on research, v1.1 should be **four sequential phases** with limited parallelization in phases 1–2.

### Phase 1: HAL Signing & Load Verification
**Rationale:** Long pole for valid DEV-01/DEV-03 on macOS 15+; ad-hoc QA wastes cycles.
**Delivers:** Signed `APM44Bridge.driver`, `apm44-bridge`, `.app`; notarytool dry-run; install runbook; `verify-hal-driver.sh` evidence on sign-off Mac.
**Addresses:** SHIP, DEV-01 (enumeration), notarization gate.
**Avoids:** Pitfalls 1–4, 10 (ad-hoc HAL, wrong cert, app-only notarization, container/staple errors, reboot/kickstart).

### Phase 2: Driver 44100-Only Hardening (DRV-02)
**Rationale:** Small Driver change; prevents Cubase/AMS rate negotiation to 48 kHz before host matrix.
**Delivers:** `SetAvailableSampleRatesAsync`; property verification; AMS single-rate proof.
**Uses:** libASPL v3.1.2 APIs (STACK).
**Avoids:** Pitfall 7 (default rate without exclusive capability).
**Note:** Can parallel Phase 1 on separate machine; sign-off listen tests need format clarity (Pitfall 8).

### Phase 3: App `--virtual-device` Integration
**Rationale:** Closes v1.0 audit gap; enables one-click production path.
**Delivers:** `HalRoutingPolicy` / `BridgeRoutingMode.swift`; `buildArguments()` branch; UI mode copy (“APM44 Bridge (driver)” vs “BlackHole”); optional routing preference override.
**Implements:** Architecture Pattern 3 (HAL presence → routing mode).
**Avoids:** Pitfalls 5–6 (wrong spawn path, hotplug losing flag, unsigned embedded helper).
**Depends on:** Stable device UID in list (Phase 1 for production validation).

### Phase 4: Cubase Sign-Off & Soak
**Rationale:** Milestone completion is human evidence on full chain, not CI-only.
**Delivers:** Cubase 15 section in `docs/daw-matrix.md`; passed matrix rows; QA-02 export artifact; 30+ min HAL soak log; optional BlackHole regression row.
**Addresses:** DEV-03, QA-01, QA-02, DEV-04.
**Avoids:** Pitfalls 9, 8 (Cubase routing, format distortion blamed on SRC).
**Requires:** Phases 1–3 on sign-off Mac.

### Phase Ordering Rationale

- **Signing before host QA** is non-negotiable on macOS 15+ — architecture and pitfalls align.
- **DRV-02 before or parallel to signing** is low risk; **before Cubase matrix** is mandatory.
- **App wiring** depends on device identity, not strictly signing for logic tests, but **APP done** requires signed HAL E2E.
- **Cubase soak last** — expensive; only after full chain works.
- **BlackHole path stays** throughout — v1.1 is additive.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (Cubase):** MEDIUM — exact Cubase 15 menu strings; operator must confirm on installed build.
- **Phase 2 (format):** If 440 Hz listen test fails — may need Float32 HAL stream research beyond v1.1 minimum.

Phases with standard patterns (skip `/gsd-research-phase`):
- **Phase 1:** Apple notarization + HAL install — well-documented (`docs/release.md`, Melatonin guide).
- **Phase 3:** Subprocess spawn + CLI flag — already in codebase; wiring only.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Apple notarization docs, libASPL API, repo `docs/release.md` |
| Features | HIGH | PROJECT.md, v1.0 audit, Steinberg Core Audio2ASIO model |
| Architecture | HIGH | Grounded in shipped v1.0 code paths |
| Pitfalls | HIGH | Audit + Driver.cpp + BridgeProcessManager.swift evidence |

**Overall confidence:** HIGH

### Gaps to Address

- **Cubase 15 UI labels:** Confirm Studio Setup / Export dialog strings on operator machine during Phase 4 planning.
- **SInt16 HAL vs float shm:** Decide fix vs. documented conversion before declaring listen-test pass; may elevate to P2 if v1.1 tone test fails.
- **CI sign-notarize:** Requires Apple secrets; keep `workflow_dispatch` until credentials exist — do not block PR CI.
- **Optional signed `.pkg` for HAL:** v1.1.1 if manual `cp` install is insufficient for first release.

## Sources

### Primary (HIGH confidence)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Creating an Audio Server Driver Plug-in](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in)
- [libASPL Device.hpp — available sample rates](https://github.com/gavv/libASPL/blob/main/include/aspl/Device.hpp)
- Repo: `.planning/PROJECT.md`, `docs/release.md`, `docs/daw-matrix.md`, `Driver/src/Driver.cpp`, `App/APM44Bridge/BridgeProcessManager.swift`

### Secondary (MEDIUM confidence)
- [tympan-aspl — macOS 15 HAL signing](https://github.com/penta2himajin/tympan-aspl)
- [Melatonin — code sign & notarize audio plugins in CI](https://melatonin.dev/blog/how-to-code-sign-and-notarize-macos-audio-plugins-in-ci/)
- Steinberg forums / Cubase 15 help — CoreAudio2ASIO, project vs export sample rate

### Detailed research files
- [STACK.md](./STACK.md) — signing toolchain, Cubase QA stack, CI
- [FEATURES.md](./FEATURES.md) — table stakes, MVP checklist, Cubase matrix
- [ARCHITECTURE.md](./ARCHITECTURE.md) — v1.1 delta, build order, integration map
- [PITFALLS.md](./PITFALLS.md) — phase mapping, recovery, “looks done but isn’t”

---
*Research completed: 2026-06-01*
*Ready for roadmap: yes*
