# Requirements: APM44 Bridge

**Defined:** 2026-06-13
**Milestone:** v0.8 Release Candidate Closure
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1 kHz
to keep playing through USB-C AirPods at 48 kHz without silent wedges or mystery
relaunches.

## v0.8 Requirements

### Signing Workflow

- [ ] **SIGN-01**: Manual signing workflow builds the `APM44Bridge` HAL driver
  target before invoking `scripts/sign-release.sh`.
- [ ] **SIGN-02**: Manual signing workflow fails when `APPLE_SIGN_ID` is missing
  instead of exiting successfully with a skip message.
- [ ] **SIGN-03**: Manual signing workflow fails when notarization is requested
  but the `AC_NOTARY` profile is unavailable.
- [ ] **SIGN-04**: Release-script regression coverage proves
  `sign-notarize.yml` builds the driver target before signing.

### Driver Notarization

- [ ] **NOTARY-01**: `scripts/notarize-hal-driver.sh` uses the shared
  `require_notary_accepted` helper for HAL driver notarization.
- [ ] **NOTARY-02**: Driver-only notarization fails on rejected, malformed, or
  unsuccessful `notarytool` results with useful logs when available.
- [ ] **NOTARY-03**: HAL driver stapling and validation still run after accepted
  driver notarization.

### Public Truth Cleanup

- [ ] **DOC-01**: Public release docs use one current version story for commands,
  artifacts, and milestone language.
- [ ] **DOC-02**: Default latency docs match the code's Safe default for new
  installs.
- [ ] **CLEAN-01**: Empty or dead legacy converter source files are deleted or
  documented with a current reason for remaining.
- [ ] **SRC-01**: SRC quality labels map to distinct converter behavior or are
  collapsed so the UI/docs do not imply placebo choices.

### Release Candidate Validation

- [ ] **QA-01**: Full local CI passes after signing workflow, notarization,
  docs, cleanup, and SRC label changes.
- [ ] **QA-02**: Release-Mac validation commands are recorded for secrets,
  release build, signing, notarization, stapling, Gatekeeper assessment, and
  installed HAL/app checks.
- [ ] **QA-03**: Operator target-hardware validation expectations are recorded
  for clean DMG install, HAL device visibility, menu-bar app start, Cubase route,
  smoke/soak, and export-rate proof.

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
| New audio/DSP architecture | v0.8 is a release-candidate closure pass, not a product expansion. |
| Signed PKG-primary public distribution | Still future/maintainer-only until installer certificate and UX validation are intentionally promoted. |
| GitHub release upload automation | Manual/operator publication remains acceptable until release workflow trust is upgraded. |
| Broad DAW validation matrix | Cubase 15 USB-C AirPods remains the release-candidate validation anchor. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SIGN-01 | Phase 30 | Pending |
| SIGN-02 | Phase 30 | Pending |
| SIGN-03 | Phase 30 | Pending |
| SIGN-04 | Phase 30 | Pending |
| NOTARY-01 | Phase 30 | Pending |
| NOTARY-02 | Phase 30 | Pending |
| NOTARY-03 | Phase 30 | Pending |
| DOC-01 | Phase 31 | Pending |
| DOC-02 | Phase 31 | Pending |
| CLEAN-01 | Phase 31 | Pending |
| SRC-01 | Phase 31 | Pending |
| QA-01 | Phase 32 | Pending |
| QA-02 | Phase 32 | Pending |
| QA-03 | Phase 32 | Pending |

**Coverage:**
- v0.8 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-06-13*
*Last updated: 2026-06-13 after v0.8 milestone initialization*
