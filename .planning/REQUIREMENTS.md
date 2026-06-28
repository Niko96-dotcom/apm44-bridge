# Requirements: APM44 Bridge v1.1 Open Source Release Confidence

**Defined:** 2026-06-28
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v1.1 Requirements

### App Quit Control

- [ ] **QUIT-01**: User can close APM44 Bridge from a visible app UI control
  without using Force Quit or Activity Monitor.
- [ ] **QUIT-02**: Quit routes through the existing app lifecycle owner so
  app-owned bridge work is stopped or intentionally left in a documented safe
  state before app termination.
- [ ] **QUIT-03**: Quit does not uninstall, reload, or mutate the privileged HAL
  driver as a side effect.
- [ ] **QUIT-04**: Quit behavior has automated coverage where practical and a
  recorded manual app-run proof for the shipped UI.

### Public Repository Surface

- [ ] **PUB-01**: README, repo description, homepage/latest-release link, and
  public docs describe the current product, supported validation target, install
  path, release artifact, and caveats without stale version claims.
- [ ] **PUB-02**: License, SECURITY, CONTRIBUTING, issue templates, and support
  expectations are present, accurate, and appropriate for a public open-source
  macOS audio utility.
- [ ] **PUB-03**: Public docs explain install, uninstall, troubleshooting,
  permissions, HAL driver behavior, and DMG-primary distribution without
  overclaiming PKG or broad DAW support.
- [ ] **PUB-04**: Public repository contents exclude private planning artifacts,
  internal agent files, credential traces, and maintainer-only local notes.

### Security and Release Hygiene

- [ ] **SEC-01**: Current tree, relevant scripts/docs, and release assets pass
  secret/private-token checks before publication.
- [ ] **SEC-02**: GitHub repository security posture is reviewed for public
  visibility, vulnerability reporting, issue templates, branch/release hygiene,
  and safe maintainer-facing instructions.
- [ ] **SEC-03**: Release automation fails closed for missing signing,
  notarization, codesign, stapling, checksum, or artifact verification inputs
  unless an explicit local-development override is used.
- [ ] **SEC-04**: Public profile/repo metadata is reviewed so links,
  descriptions, release notes, and support channels do not expose private
  information or misleading claims.

### Verification and Release Publication

- [ ] **REL-01**: Full local CI passes from the release candidate, including
  secret scan, native tests, Swift tests, release-script regressions, app embed,
  and installed-sync dry-run.
- [ ] **REL-02**: Installed app/helper/driver proof is recorded with current
  build identities before claiming the running installed version is current.
- [ ] **REL-03**: Public release artifact evidence records signing,
  notarization, stapling, Gatekeeper validation, checksums, and exact artifact
  names, or records a publication blocker instead of uploading.
- [ ] **REL-04**: GitHub latest release is published or updated only after the
  release gate passes, and the latest release page, assets, tag, checksums, and
  README/latest links are verified afterward.
- [ ] **REL-05**: Any remaining operator-dependent Cubase 15 / USB-C AirPods Max
  soak or hardware caveat is explicitly documented in release notes rather than
  implied as complete.

## Future Requirements

- **PKG-01**: Promote signed PKG installer to public distribution after
  Developer ID Installer validation and installer UX are intentionally shipped.
- **COMP-01**: Add Logic/Ableton compatibility matrix after target DAW evidence
  exists.
- **SUPP-01**: Add support bundle export for public troubleshooting.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Signed PKG-primary release | Future until Developer ID Installer path and UX are validated. |
| Broad DAW compatibility claims | Cubase 15 remains the validation anchor for this milestone. |
| Realtime DSP/resampler architecture changes | v1.1 is release confidence plus Quit UI, not audio-engine replacement. |
| Publishing `.planning/` publicly | GSD artifacts remain local/ignored unless explicitly chosen later. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| QUIT-01 | Phase 42 | Pending |
| QUIT-02 | Phase 42 | Pending |
| QUIT-03 | Phase 42 | Pending |
| QUIT-04 | Phase 42 | Pending |
| PUB-01 | Phase 43 | Pending |
| PUB-02 | Phase 43 | Pending |
| PUB-03 | Phase 43 | Pending |
| PUB-04 | Phase 43 | Pending |
| SEC-01 | Phase 44 | Pending |
| SEC-02 | Phase 44 | Pending |
| SEC-03 | Phase 44 | Pending |
| SEC-04 | Phase 44 | Pending |
| REL-01 | Phase 44 | Pending |
| REL-02 | Phase 44 | Pending |
| REL-03 | Phase 44 | Pending |
| REL-04 | Phase 45 | Pending |
| REL-05 | Phase 45 | Pending |

**Coverage:**
- v1.1 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-06-28*
*Last updated: 2026-06-28 after initial definition*
