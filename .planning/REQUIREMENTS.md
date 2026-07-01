# Requirements: APM44 Bridge v1.2 Professional Installer and Release Hygiene

**Defined:** 2026-07-01
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v1.2 Requirements

### PKG Installer Promotion

- [x] **PKG-01**: User can install or upgrade APM44 Bridge through a
  Developer ID Installer-signed `.pkg` that installs the menu bar app and HAL
  driver to their intended system locations.
- [x] **PKG-02**: Maintainer release mode fails before publication if a valid
  Developer ID Installer identity is unavailable or the package is unsigned.
- [x] **PKG-03**: Maintainer can notarize, staple, validate, and Gatekeeper
  assess the final `.pkg` before it is wrapped or published.
- [x] **PKG-04**: The package install path preserves signed/stapled app and
  driver payload integrity and records a deterministic app/helper/driver build
  identity.
- [x] **PKG-05**: The package handles first install and upgrade over an existing
  APM44 Bridge install without leaving stale app, helper, or HAL driver files.

### Professional DMG Presentation

- [x] **DMG-01**: User opening the public DMG sees a clear product-grade
  installer entrypoint instead of raw app, HAL driver, and Terminal command
  contents.
- [x] **DMG-02**: The public DMG contains the validated installer package as the
  primary install object and excludes raw `APM44 Bridge.app`,
  `APM44Bridge.driver`, and `.command` installer internals.
- [x] **DMG-03**: Maintainer release mode signs, notarizes, staples, validates,
  and Gatekeeper assesses the final DMG after all contents are final.
- [x] **DMG-04**: Maintainer can mount the final DMG and run an automated layout
  check that proves the visible contents match the expected professional
  installer flow.
- [x] **DMG-05**: Checksums are generated only after final PKG and DMG stapling
  so published checksum files match the exact release bytes.

### Install, Upgrade, and Uninstall Proof

- [x] **INST-01**: Maintainer can install APM44 Bridge from the final mounted
  DMG/PKG path, not from repo build output, and record that install proof.
- [x] **INST-02**: Installed `/Applications/APM44 Bridge.app`, embedded helper,
  and `/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver` match the validated
  release build identities after install.
- [x] **INST-03**: Installed HAL driver proof passes Gatekeeper, Core Audio
  visibility, and `apm44-bridge --shm-status` checks before release
  publication.
- [x] **INST-04**: Upgrade validation proves installing v1.2 over the current
  latest public release replaces stale app/helper/driver state.
- [x] **INST-05**: User has a documented and verified uninstall path that
  removes the app and HAL driver without leaving misleading release claims or
  stale instructions.

### Public Docs and Release Truth

- [ ] **DOC-01**: Public install docs describe the PKG-primary flow, expected
  admin prompt, HAL driver location, Core Audio reload or reboot caveat, and
  first-run checks in user-facing language.
- [ ] **DOC-02**: Maintainer release docs and validation checklists match the
  new PKG-in-DMG public artifact flow and no longer call PKG maintainer-only.
- [ ] **DOC-03**: README, release notes, and GitHub release text identify the
  supported Cubase 15 / USB-C AirPods Max validation target and any remaining
  operator-dependent caveats.
- [ ] **DOC-04**: Public repo hygiene checks prove `.planning/`, `.DS_Store`,
  certificate/private-key material, notary logs, and maintainer-only local
  artifacts are not tracked or published.

### Release Hygiene and Publication

- [ ] **REL-01**: Full local CI passes from a clean release candidate before
  signing or publication.
- [ ] **REL-02**: Release automation fails closed for missing signing,
  notarization, stapling, package signature, Gatekeeper assessment, checksum,
  mounted-DMG layout, install proof, installed-sync, or HAL proof gates unless a
  clearly local-only override is used.
- [ ] **REL-03**: Maintainer can produce final public artifacts from a clean
  commit/tag with non-dirty version identity and recorded checksums.
- [ ] **REL-04**: GitHub latest release is created or updated only after the
  release gate passes, with accurate release notes and all intended assets
  uploaded.
- [ ] **REL-05**: Maintainer downloads the published GitHub assets and rechecks
  checksums, package signature/notary state, DMG layout, and release provenance
  before declaring the milestone shipped.

## Future Requirements

- **UI-01**: Add richer custom Installer distribution screens or localized
  resources if the basic signed PKG flow needs more guidance.
- **FRESH-01**: Add fresh-machine or VM-style automated install validation.
- **COMP-01**: Add Logic/Ableton compatibility matrix after target DAW evidence
  exists.
- **SUPP-01**: Add support bundle export for public troubleshooting.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Raw app/driver/command public DMG install path | Superseded by professional PKG-primary installation. |
| Broad DAW compatibility claims | Cubase 15 remains the validation anchor for this milestone. |
| Realtime DSP/resampler architecture changes | v1.2 is installer and release hygiene work, not audio-engine replacement. |
| Publishing `.planning/` publicly | GSD artifacts remain local/ignored to protect public repo hygiene. |
| Skipping live installed-system proof for a clean release claim | The user explicitly chose the full release bar, including installed sync and HAL proof. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PKG-01 | Phase 46 | Complete |
| PKG-02 | Phase 46 | Complete |
| PKG-03 | Phase 46 | Complete |
| PKG-04 | Phase 46 | Complete |
| PKG-05 | Phase 46 | Complete |
| DMG-01 | Phase 47 | Complete |
| DMG-02 | Phase 47 | Complete |
| DMG-03 | Phase 47 | Complete |
| DMG-04 | Phase 47 | Complete |
| DMG-05 | Phase 47 | Complete |
| INST-01 | Phase 48 | Complete |
| INST-02 | Phase 48 | Complete |
| INST-03 | Phase 48 | Complete |
| INST-04 | Phase 48 | Complete |
| INST-05 | Phase 48 | Complete |
| DOC-01 | Phase 49 | Pending |
| DOC-02 | Phase 49 | Pending |
| DOC-03 | Phase 49 | Pending |
| DOC-04 | Phase 49 | Pending |
| REL-01 | Phase 49 | Pending |
| REL-02 | Phase 49 | Pending |
| REL-03 | Phase 50 | Pending |
| REL-04 | Phase 50 | Pending |
| REL-05 | Phase 50 | Pending |

**Coverage:**
- v1.2 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0

---
*Requirements defined: 2026-07-01*
*Last updated: 2026-07-01 after v1.2 roadmap traceability mapping*
