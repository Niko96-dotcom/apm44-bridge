# Requirements: APM44 Bridge

**Defined:** 2026-06-13
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1 kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or mystery relaunches.

## v1 Requirements

Requirements for the v0.6 Public Release Safety Fixes milestone.

### HAL Runtime Safety

- [ ] **HAL-01**: HAL mono-lane output rejects unrelated left/right timestamp mismatches and never pairs arbitrary mismatched lanes into stereo shm output.
- [ ] **HAL-02**: HAL mono-lane rollover pairing is allowed only through a named predicate that compares `zeroTimestamp + timestamp` within a narrow documented tolerance.
- [ ] **HAL-03**: HAL mixed-output processing ignores callbacks when IO is stopped, before stream processing or shm writes occur.
- [ ] **HAL-04**: HAL shm push comments accurately describe the implemented drop-new/incoming-tail policy.

### Converter and Metrics Safety

- [ ] **CONV-01**: The public daemon no longer exposes the unsafe legacy AudioToolbox converter debug path through CLI help, parsing, docs, build inputs, or runtime engine options.
- [ ] **METR-04**: Realtime metrics publication stores floating payload fields with a lock-free representation and no `std::atomic<double>` in the realtime publisher state.

### App Lifecycle Reliability

- [ ] **APP-06**: Device catalog refresh cannot deadlock on helper stderr output while listing audio devices.
- [ ] **APP-07**: Metrics state reset clears `latestMetrics`, `lastMetricsAt`, and `metricsStale` together on start and idle transitions.

### Release Automation

- [ ] **DIST-05**: The DMG command installer replaces `/Applications/APM44 Bridge.app` deterministically by removing any existing bundle, copying with privileged `ditto`, and setting root ownership.
- [ ] **CI-02**: GitHub CI runs `tests/test_release_scripts.sh` so release-script regressions fail the public CI gate.

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
| Fixing and retaining `--legacy-converter` | Public-release minimization is safer than carrying an unnecessary debug SRC path. |
| New DSP/resampler architecture | v0.6 is about release-safety blockers, not audio-engine replacement. |
| Bluetooth-only AirPods reliability | USB-C AirPods Max is the product target for this bridge. |
| Broad DAW expansion | Cubase 15 HAL path remains the validation anchor. |
| LaunchAgent daemon auto-start | Superseded for now by the menu bar app and Open at Login. |
| Live operator soak sign-off | Hardware-dependent; repo tests and release-script gates are in scope, target-machine soak is not. |
| PKG-primary promotion | The DMG command installer is hardened in v0.6; PKG-primary remains a separate signed-installer milestone. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HAL-01 | — | Pending |
| HAL-02 | — | Pending |
| HAL-03 | — | Pending |
| HAL-04 | — | Pending |
| CONV-01 | — | Pending |
| METR-04 | — | Pending |
| APP-06 | — | Pending |
| APP-07 | — | Pending |
| DIST-05 | — | Pending |
| CI-02 | — | Pending |

**Coverage:**
- v1 requirements: 10 total
- Mapped to phases: 0
- Unmapped: 10

---
*Requirements defined: 2026-06-13*
*Last updated: 2026-06-13 after v0.6 requirements definition*
