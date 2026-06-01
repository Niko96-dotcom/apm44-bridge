# Roadmap: APM44 Bridge

## Milestones

- ✅ **v1.0 APM44 Bridge MVP** — Phases 1–5 (shipped 2026-06-01)
- 🚧 **v1.1 Production Sign-Off** — Phases 6–9 (in progress)

## Overview

v1.0 delivered the full audio stack (BlackHole MVP, libsamplerate/drift engine, menu bar app, HAL driver + shm, integration docs). **v1.1** closes production credibility: **Developer ID–signed HAL** that loads on macOS 15+, **44100-only** driver contract, menu bar that spawns **`--virtual-device`** when the driver is present, and **human sign-off on Cubase 15** (30+ min HAL soak + export @ 44.1 kHz). Signing is a hard gate before host QA; Cubase matrix runs on unsigned HAL are out of scope for milestone complete.

## Phases

<details>
<summary>✅ v1.0 APM44 Bridge MVP (Phases 1–5) — SHIPPED 2026-06-01</summary>

- [x] **Phase 1: BlackHole Console Bridge** (4/4 plans) — completed 2026-06-01
- [x] **Phase 2: Production SRC & Drift Engine** (6/6 plans) — completed 2026-06-01
- [x] **Phase 3: Menu Bar Application** (7/7 plans) — completed 2026-06-01
- [x] **Phase 4: HAL Virtual Device** (5/5 plans) — completed 2026-06-01
- [x] **Phase 5: Integration & Ship Readiness** (1/1 plans) — completed 2026-06-01

Full phase details: [.planning/milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

### 🚧 v1.1 Production Sign-Off (In Progress)

**Milestone goal:** A producer on a sign-off Mac can run **Cubase 15** @ 44.1 kHz → **APM44 Bridge** (signed HAL) → AirPods Max USB-C @ 48 kHz with documented signing/notarization evidence and passed soak + export validation.

- [x] **Phase 6: HAL Signing & Load Verification** — Developer ID sign scripts; notary dry-run; verify-hal-driver enhancements
- [x] **Phase 7: Driver 44100-Only Hardening** — SetAvailableSampleRatesAsync 44100 only
- [x] **Phase 8: App Virtual-Device Integration** — Menu bar spawns `--virtual-device`; routing mode UI
- [ ] **Phase 9: Cubase Sign-Off & Soak** — Operator templates ready; human 30+ min soak + export pending
- [x] **Phase 10: Product Distribution & First-Run** — pkg/DMG scripts, embedded daemon, first-run preflight

## Phase Details

### Phase 6: HAL Signing & Load Verification
**Goal**: Signed, notarization-ready release artifacts load the HAL on a real Mac and enumerate **APM44 Bridge** in Audio MIDI Setup @ 44.1 kHz
**Depends on**: v1.0 Phases 1–5 (shipped)
**Requirements**: SHIP-01, SHIP-02, SHIP-03, DEV-01
**Success Criteria** (what must be TRUE):
  1. Operator installs signed `APM44Bridge.driver` to `/Library/Audio/Plug-Ins/HAL/` and **APM44 Bridge** appears in Audio MIDI Setup as a **stereo output at 44,100 Hz** after HAL reload (or reboot if required)
  2. `verify-hal-driver.sh` (or equivalent) passes on the sign-off Mac — signed plug-in loaded in **coreaudiod**, device UID visible
  3. `APM44Bridge.driver`, `apm44-bridge`, and `APM44 Bridge.app` each verify as **Developer ID Application** with **Hardened Runtime** (`codesign --verify --deep --strict`)
  4. Release container (zip/dmg/pkg) completes **`notarytool` dry-run**; staple workflow is documented with evidence captured on the sign-off Mac
**Plans**: TBD

### Phase 7: Driver 44100-Only Hardening
**Goal**: DAW and AMS cannot negotiate the virtual device away from 44.1 kHz — only **44100 Hz** is offered as a nominal rate
**Depends on**: Phase 6 (signed load recommended for sign-off verification; logic can be developed in parallel on dev machines)
**Requirements**: DRV-02
**Success Criteria** (what must be TRUE):
  1. Audio MIDI Setup shows **only 44,100 Hz** (no 48 kHz or other rates) as selectable nominal sample rate for **APM44 Bridge**
  2. Property inspection confirms available nominal sample rates are **44100-only** (e.g. `SetAvailableSampleRatesAsync({44100, 44100})` — not default-rate-only)
  3. Attempting to set another nominal rate on the virtual device is rejected or has no effect (device stays 44.1 kHz capable only)
**Plans**: TBD

### Phase 8: App Virtual-Device Integration
**Goal**: One-click menu bar control runs the production HAL path when the driver is installed, with clear routing mode feedback
**Depends on**: Phase 6 (production E2E validation); Phase 7 (rate contract stable before Cubase matrix)
**Requirements**: APP-06, APP-07
**Success Criteria** (what must be TRUE):
  1. With HAL installed and detected, user starts bridge from menu bar and daemon launches with **`--virtual-device`** (verified spawn argv)
  2. With HAL absent, user can still start bridge on the **BlackHole** path without error (documented fallback unchanged)
  3. Menu bar UI shows whether **APM44 Bridge (driver)** or **BlackHole** routing mode is active before and during playback
  4. Hotplug or HAL install/uninstall updates routing mode indication within one debounced refresh cycle
**Plans**: TBD
**UI hint**: yes

### Phase 9: Cubase Sign-Off & Soak
**Goal**: Human evidence that the full production chain works for the primary DAW host — stable long-session monitoring and honest 44.1 kHz exports
**Depends on**: Phases 6, 7, 8 complete on sign-off Mac (signed HAL + 44100-only + correct app spawn)
**Requirements**: DEV-03, DEV-04, QA-01, QA-02
**Success Criteria** (what must be TRUE):
  1. User runs **Cubase 15** with project at **44.1 kHz**, playback routed to **APM44 Bridge**, and hears stable monitoring on **AirPods Max USB-C** via the bridge daemon (HAL path, not BlackHole-only)
  2. While HAL production path is active, **AirPods Max USB-C** remain at **48,000 Hz** in Audio MIDI Setup (regression vs forcing headphones to 44.1 kHz)
  3. Operator completes **30+ minutes** continuous playback on the HAL path without crackle, unbounded latency growth, or drift-induced dropouts (logged soak evidence)
  4. **Cubase 15** export or bounce of a 44.1 kHz project produces files verified at **44,100 Hz** by `scripts/validate-export-rate.sh` and `afinfo`
**Plans**: TBD

### Phase 10: Product Distribution & First-Run
**Goal**: A producer installs one notarized artifact, uses the menu bar app only (no Terminal), and completes a short first-run wizard before Cubase playback
**Depends on**: Phase 6 (signed/notarized binaries); Phase 8 (`--virtual-device` + routing UI)
**Requirements**: POL-01, SHIP-02
**Success Criteria** (what must be TRUE):
  1. **Notarized DMG or pkg** installs `APM44 Bridge.app` and `APM44Bridge.driver` with a single documented admin step; postinstall reloads Core Audio
  2. **`apm44-bridge` is embedded** in the app bundle; `BridgeBinaryLocator` resolves it with no `APM44_BRIDGE_PATH` required for release builds
  3. **First-run / preflight UI** in the menu bar app checks: driver loaded, APM44 @ 44.1 kHz, AirPods USB @ 48 kHz, and links to **Cubase 15** Control Room port checklist
  4. **Release signing scripts** (`sign-release.sh` or Xcode copy phase) produce stapled driver + app in one CI/local command documented in `docs/release.md`
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution order (v1.1):** 6 → 7 → 8 → 9 → 10 (Phase 7 may parallel Phase 6 on dev machines; Phases 8–10 require signed HAL on sign-off Mac)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. BlackHole Console Bridge | v1.0 | 4/4 | Complete | 2026-06-01 |
| 2. Production SRC & Drift Engine | v1.0 | 6/6 | Complete | 2026-06-01 |
| 3. Menu Bar Application | v1.0 | 7/7 | Complete | 2026-06-01 |
| 4. HAL Virtual Device | v1.0 | 5/5 | Complete | 2026-06-01 |
| 5. Integration & Ship Readiness | v1.0 | 1/1 | Complete | 2026-06-01 |
| 6. HAL Signing & Load Verification | v1.1 | 1/1 | Complete | 2026-06-01 |
| 7. Driver 44100-Only Hardening | v1.1 | 1/1 | Complete | 2026-06-01 |
| 8. App Virtual-Device Integration | v1.1 | 2/2 | Complete | 2026-06-01 |
| 9. Cubase Sign-Off & Soak | v1.1 | 1/1 | Human QA pending | - |
| 10. Product Distribution & First-Run | v1.1 | 1/1 | Complete | 2026-06-01 |

---
*Roadmap updated: 2026-06-01 — milestone v1.1 Production Sign-Off (Phases 6–10)*
