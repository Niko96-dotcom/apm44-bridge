# Requirements: APM44 Bridge

**Defined:** 2026-06-01 (milestone v1.1)
**Core Value:** DAW sessions stay at 44.1 kHz while monitoring stably on AirPods Max USB-C at 48 kHz via a virtual bridge endpoint.

## v1.1 Requirements

Production sign-off — close v1.0 audit gaps with **Cubase 15** as the primary DAW matrix host.

### Distribution & signing (SHIP)

- [ ] **SHIP-01**: All shipped binaries (`APM44Bridge.driver`, `apm44-bridge`, `APM44 Bridge.app`) are signed with **Developer ID Application** and **Hardened Runtime**
- [ ] **SHIP-02**: Release container (zip/dmg/pkg) passes **`notarytool` dry-run** and staple workflow documented with evidence on sign-off Mac
- [ ] **SHIP-03**: Signed HAL plug-in loads in **`coreaudiod`** and is enumerated in Audio MIDI Setup (verified by `verify-hal-driver.sh` or equivalent)

### Virtual device & DAW integration (DEV)

- [ ] **DEV-01**: User sees **APM44 Bridge** in Audio MIDI Setup as a stereo output @ **44,100 Hz** after signed install and HAL reload
- [ ] **DEV-03**: User can run **Cubase 15** with project @ **44.1 kHz**, playback routed to **APM44 Bridge**, and hear monitoring on AirPods Max USB-C via the bridge daemon
- [ ] **DEV-04**: Physical AirPods Max USB-C endpoint remains at **48,000 Hz** in AMS while the HAL production path is active (regression check)

### Production driver (DRV)

- [ ] **DRV-02**: Driver advertises **44100 Hz only** in available nominal sample rates (`SetAvailableSampleRatesAsync` or equivalent libASPL API)

### Application integration (APP)

- [ ] **APP-06**: Menu bar app spawns `apm44-bridge` with **`--virtual-device`** when the HAL driver is installed and detected; **BlackHole path remains** available fallback when HAL is absent
- [ ] **APP-07**: Menu bar UI indicates active routing mode (**APM44 Bridge (driver)** vs **BlackHole**) so the user knows which path is running

### Quality & validation (QA)

- [ ] **QA-01**: Operator completes **30+ minutes** continuous playback on the **HAL path** (Cubase → APM44 Bridge → daemon → AirPods) without crackle, unbounded latency growth, or drift-induced dropouts
- [ ] **QA-02**: **Cubase 15** export or bounce of a 44.1 kHz project produces audio files verified @ **44,100 Hz** by `scripts/validate-export-rate.sh` (and `afinfo`)

## Future Requirements

Deferred beyond v1.1 — acknowledged for roadmap hygiene.

### Other DAW hosts

- **DEV-05**: Logic Pro and Ableton Live matrix rows (operator does not have these hosts for v1.1)

### Product polish

- **POL-01**: Full installer/pkg automation and staple-in-CI
- **POL-02**: HAL stream format hardening (Float32 end-to-end vs SInt16 in driver) if listen tests expose issues
- **POL-03**: XPC daemon control (replace subprocess spawn)

### Pro Tools & advanced routing

- **PT-01**: APM44 Bridge Pro unified virtual playback engine (v2)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Logic/Ableton as v1.1 blockers | Operator sign-off machine has Cubase 15 only |
| Remove BlackHole MVP path | Explicit v1.1 decision: keep documented fallback |
| Signing docs without signed HAL load test | Hard gate — milestone not done without SHIP-03 |
| Force AirPods nominal rate to 44.1 kHz | Hardware exposes 48 kHz only |
| Pro Tools unified engine | v2 per PROJECT.md |
| Bluetooth-only AirPods | USB-C wired scope |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SHIP-01 | Phase 6 | Pending |
| SHIP-02 | Phase 6 | Pending |
| SHIP-03 | Phase 6 | Pending |
| DEV-01 | Phase 6 | Pending |
| DRV-02 | Phase 7 | Pending |
| APP-06 | Phase 8 | Pending |
| APP-07 | Phase 8 | Pending |
| DEV-03 | Phase 9 | Pending |
| DEV-04 | Phase 9 | Pending |
| QA-01 | Phase 9 | Pending |
| QA-02 | Phase 9 | Pending |

**Coverage:**
- v1.1 requirements: 11 total
- Mapped to phases: 11 ✓
- Unmapped: 0

---
*Requirements defined: 2026-06-01 — milestone v1.1 Production Sign-Off*
*Last updated: 2026-06-01 — traceability synced to ROADMAP.md (Phases 6–9)*
