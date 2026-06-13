# Requirements: APM44 Bridge

**Defined:** 2026-06-13
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1 kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or mystery relaunches.

## v1 Requirements

Requirements for the v0.5 Release Readiness Hardening milestone.

### Metrics & Serialization

- [ ] **METR-01**: `MetricsPublisher` stores snapshot fields atomically (or via an equivalent RT-safe representation) so publication is data-race-free under standard C++.
- [ ] **METR-02**: Metrics publication passes ThreadSanitizer without reported races.
- [ ] **METR-03**: `BridgeMetrics::ToJsonLine` handles `snprintf` truncation safely and cannot read past its stack buffer.

### Core Audio Error Paths

- [ ] **CORE-01**: Virtual-device output-start failure only stops an input IOProc if one was actually created and started.
- [ ] **CORE-02**: Non-interleaved input callback clamps both buffer sizes before passing channels to the engine.

### Release Automation

- [ ] **REL-01**: `notarize-release-dmg.sh` treats any non-`Accepted` notarization result or nonzero exit status as a hard failure.
- [ ] **REL-02**: `release-all.sh` requires an explicit override (e.g. `APM44_ALLOW_UNNOTARIZED=1`) to produce an unnotarized artifact.
- [ ] **REL-03**: `sign-notarize.yml` fails hard if `verify-app-build.sh` fails.

### Security & Realtime Cleanup

- [ ] **SEC-01**: Public docs include a clear local IPC threat model for shared-memory mode `0666` with no security overclaiming.
- [ ] **SEC-02**: Realtime overrun helper name/comments accurately describe drop-new-input behavior.
- [ ] **SEC-03**: Unused or incorrect `WriteSilence` helper is removed or rewritten.

### Distribution & CI

- [ ] **DIST-01**: DMG creation order staples inner app/driver artifacts before building the final DMG, then notarizes/staples the DMG.
- [ ] **DIST-02**: Public docs explain signed PKG direction and current DMG-primary posture.
- [ ] **CI-01**: Release-facing GitHub Actions are pinned by SHA or the decision not to is explicitly documented.

### QA / Regression

- [ ] **QA-01**: Regression tests cover the fixed truncation, failure-path, and callback-edge cases.
- [ ] **QA-02**: Clean release validation sequence runs successfully after all fixes.

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Distribution

- **DIST-03**: Signed PKG installer becomes the primary public install path.
- **DIST-04**: GitHub release publication/upload is fully automated in CI.

### Compatibility

- **COMP-01**: Logic/Ableton validation matrix.

### Observability

- **OBSV-01**: Support bundle export.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| New DSP/resampler architecture | v0.5 is about release-blocking correctness and distribution hardening, not audio-engine replacement. |
| Bluetooth-only AirPods reliability | USB-C AirPods Max is the product target for this bridge. |
| Broad DAW expansion | Cubase 15 HAL path remains the validation anchor. |
| LaunchAgent daemon auto-start | Superseded for now by the menu bar app and Open at Login. |
| Live operator soak sign-off | Hardware-dependent; repo tests and release-artifact gates are in scope, target-machine soak is not. |
| Full SHA pinning of every workflow | Only release/signing/notarization workflows are in scope; other Actions remain tag-pinned with Dependabot. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| METR-01 | Phase 17 | Pending |
| METR-02 | Phase 17 | Pending |
| METR-03 | Phase 17 | Pending |
| CORE-01 | Phase 18 | Pending |
| CORE-02 | Phase 18 | Pending |
| REL-01 | Phase 19 | Pending |
| REL-02 | Phase 19 | Pending |
| REL-03 | Phase 19 | Pending |
| SEC-01 | Phase 20 | Pending |
| SEC-02 | Phase 20 | Pending |
| SEC-03 | Phase 20 | Pending |
| DIST-01 | Phase 21 | Pending |
| DIST-02 | Phase 21 | Pending |
| CI-01 | Phase 21 | Pending |
| QA-01 | Phase 22 | Pending |
| QA-02 | Phase 22 | Pending |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-13*
*Last updated: 2026-06-13 after v0.5 roadmap creation*
