# Requirements: APM44 Bridge

**Defined:** 2026-06-13
**Milestone:** v0.7 Release Automation Final Polish
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1 kHz
to keep playing through USB-C AirPods at 48 kHz without silent wedges or mystery
relaunches.

## v0.7 Requirements

### Signing Workflow

- [ ] **SIGN-01**: Manual signing workflow builds the Release app with
  `xcodebuild -configuration Release`.
- [ ] **SIGN-02**: Manual signing workflow writes that app to
  `build/Release/APM44 Bridge.app`.
- [ ] **SIGN-03**: Manual signing workflow signs and verifies the same Release
  app artifact.

### CI App Bundle Proof

- [ ] **CI-01**: `scripts/ci.sh` builds or locates the app bundle it intends to
  verify.
- [ ] **CI-02**: `scripts/ci.sh` embeds the current daemon into that exact app
  bundle.
- [ ] **CI-03**: Installed-sync verification fails if the checked app bundle is
  missing the embedded helper.

### Release Verification

- [ ] **REL-01**: Release codesign verification fails on missing Hardened
  Runtime unless explicitly overridden.
- [ ] **REL-02**: Release codesign verification fails on missing Developer ID
  Application identity unless explicitly overridden.

### Runtime Guardrails

- [ ] **METR-01**: Metrics packed `std::atomic<uint64_t>` storage has a
  compile-time lock-free assertion.
- [ ] **APP-01**: Clean running-process termination goes through the central
  idle transition/reset path.
- [ ] **QA-01**: Full final release-polish verification covers signing workflow,
  CI bundle proof, codesign strictness, metrics lock-free guard, and process
  termination reset.

## Future Requirements

Deferred to future milestones and tracked only as context.

### Distribution

- **DIST-01**: Signed PKG installer path can be promoted from maintainer-only to
  public distribution after Developer ID Installer validation and installer UX
  hardening.
- **DIST-02**: GitHub release publication/upload can be automated after the
  signing/notarization trust posture is explicitly upgraded.

### Compatibility

- **COMP-01**: Logic and Ableton validation can expand the DAW matrix after the
  Cubase 15 USB-C AirPods path remains stable.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New audio/DSP behavior | v0.7 is a narrow final release automation polish pass. |
| Signed PKG-primary public distribution | Still future/maintainer-only until installer certificate and UX validation are intentionally promoted. |
| GitHub release upload automation | Manual/operator publication remains acceptable until release workflow trust is upgraded. |
| Live USB-C AirPods/Cubase soak | Operator hardware validation remains outside local automation for this milestone. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SIGN-01 | Phase 27 | Pending |
| SIGN-02 | Phase 27 | Pending |
| SIGN-03 | Phase 27 | Pending |
| CI-01 | Phase 27 | Pending |
| CI-02 | Phase 27 | Pending |
| CI-03 | Phase 27 | Pending |
| REL-01 | Phase 28 | Pending |
| REL-02 | Phase 28 | Pending |
| METR-01 | Phase 28 | Pending |
| APP-01 | Phase 28 | Pending |
| QA-01 | Phase 29 | Pending |

**Coverage:**
- v0.7 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-06-13*
*Last updated: 2026-06-13 after roadmap creation*
