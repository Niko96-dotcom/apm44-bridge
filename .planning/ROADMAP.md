# Roadmap: APM44 Bridge

## Milestones

- Complete **v0.1.0 Initial Distribution** - Phases 1-4 (shipped 2026-06-01)
- Complete **v0.1.1 Public Release** - HAL dropout recovery, metrics clarity,
  notarized DMG (shipped 2026-06-03)
- Complete **v0.2 Reliability and Self-Healing** - Phases 5-8 (shipped
  2026-06-11) - [archive](milestones/v0.2-ROADMAP.md)
- Complete **v0.3 Realtime Audio Hardening** - Phases 9-12 (shipped
  2026-06-12) - [archive](milestones/v0.3-ROADMAP.md)
- Complete **v0.4 Public Release Blocker Closure** - Phases 13-16 (shipped
  2026-06-12) - [archive](milestones/v0.4-ROADMAP.md)
- Complete **v0.5 Release Readiness Hardening** - Phases 17-22 (shipped
  2026-06-13) - [archive](milestones/v0.5-ROADMAP.md)
- Complete **v0.6 Public Release Safety Fixes** - Phases 23-26 (shipped
  2026-06-13) - [archive](milestones/v0.6-ROADMAP.md)
- Complete **v0.7 Release Automation Final Polish** - Phases 27-29 (shipped
  2026-06-13) - [archive](milestones/v0.7-ROADMAP.md)
- Complete **v0.8 Release Candidate Closure** - Phases 30-32 (shipped
  2026-06-13) - [archive](milestones/v0.8-ROADMAP.md)
- Complete **v0.9 Public Polish Final Hardening** - Phases 33-37 (shipped
  2026-06-14) - [archive](milestones/v0.9-ROADMAP.md)
- Complete **v1.0 Realtime Race Blocker Closure** - Phases 38-41 (shipped
  2026-06-14) - [archive](milestones/v1.0-ROADMAP.md)
- Reconciled **v1.1 Open Source Release Confidence** - Phases 42-45
  (reconciled 2026-07-01) - [archive](milestones/v1.1-ROADMAP.md)
- Active **v1.2 Professional Installer and Release Hygiene** - Phases 46-50

## Current Status

v1.2 replaces the current folder-style DMG experience with a professional
Developer ID Installer-signed PKG flow, then runs a full clean-release gate
before publishing the next GitHub latest release.

## Phase Numbering

Phase numbering continues from shipped and reconciled history:

- Phases 1-4: v0.1/v0.1.1 shipped product path.
- Phases 5-8: v0.2 Reliability and Self-Healing.
- Phases 9-12: v0.3 Realtime Audio Hardening.
- Phases 13-16: v0.4 Public Release Blocker Closure.
- Phases 17-22: v0.5 Release Readiness Hardening.
- Phases 23-26: v0.6 Public Release Safety Fixes.
- Phases 27-29: v0.7 Release Automation Final Polish.
- Phases 30-32: v0.8 Release Candidate Closure.
- Phases 33-37: v0.9 Public Polish Final Hardening.
- Phases 38-41: v1.0 Realtime Race Blocker Closure.
- Phases 42-45: v1.1 Open Source Release Confidence.
- Phases 46-50: v1.2 Professional Installer and Release Hygiene.

## Active Milestone: v1.2 Professional Installer and Release Hygiene

| Phase | Name | Goal | Requirements |
|-------|------|------|--------------|
| 46 | 4/4 | Complete    | 2026-07-01 |
| 47 | Professional DMG Presentation | Make the opened DMG feel product-grade and expose the PKG installer instead of raw internals. | DMG-01, DMG-02, DMG-03, DMG-04, DMG-05 |
| 48 | Install, Upgrade, and Uninstall Proof | Prove the final mounted artifact installs, upgrades, and uninstalls cleanly with current app/helper/HAL state. | INST-01, INST-02, INST-03, INST-04, INST-05 |
| 49 | Public Docs and Release Hygiene Gate | Align public docs with the PKG flow and make release automation fail closed before publication. | DOC-01, DOC-02, DOC-03, DOC-04, REL-01, REL-02 |
| 50 | Latest Release Publication Closure | Publish the clean release to GitHub and reverify the public downloaded assets. | REL-03, REL-04, REL-05 |

## Phase Progress

- [x] **Phase 46: PKG Installer Promotion** - Signed/notarized/stapled PKG public path. (completed 2026-07-01)
- [ ] **Phase 47: Professional DMG Presentation** - PKG-first DMG wrapper and layout proof.
- [ ] **Phase 48: Install, Upgrade, and Uninstall Proof** - Real final-artifact install proof and installed HAL verification.
- [ ] **Phase 49: Public Docs and Release Hygiene Gate** - Docs, CI, secrets, fail-closed release checks.
- [ ] **Phase 50: Latest Release Publication Closure** - Clean tag/release, GitHub assets, downloaded-asset proof.

### Phase 46: PKG Installer Promotion

**Goal:** Promote the package installer from maintainer-only experiment to
fail-closed public install artifact.

**Requirements:** PKG-01, PKG-02, PKG-03, PKG-04, PKG-05

**Plans:** 4/4 plans complete

Plans:
- [x] 46-01-PLAN.md — Fail-closed package identity and payload staging.
- [x] 46-02-PLAN.md — Package notarization, validation, Gatekeeper assessment, and checksum.
- [x] 46-03-PLAN.md — Mandatory release-all package gate promotion.
- [x] 46-04-PLAN.md — Package upgrade semantics, verifier, and provenance handoff.

**Success criteria:**
1. Public release mode builds a Developer ID Installer-signed package that
   installs `APM44 Bridge.app` and `APM44Bridge.driver` to the intended paths.
2. Missing or ambiguous Developer ID Installer identity blocks public package
   output instead of warning and continuing.
3. Package notarization, stapling, `pkgutil --check-signature`, and
   `spctl --assess --type install` are automated release gates.
4. Package payload preserves signed/stapled app and driver integrity and records
   deterministic build identity.
5. Package upgrade behavior removes stale app/helper/driver state from the
   current latest public release.

### Phase 47: Professional DMG Presentation

**Goal:** Make the opened DMG feel product-grade and expose the PKG installer
instead of raw internals.

**Requirements:** DMG-01, DMG-02, DMG-03, DMG-04, DMG-05

**Success criteria:**
1. Final DMG contains the validated installer package as the obvious primary
   install object.
2. Final DMG does not expose raw `APM44 Bridge.app`, `APM44Bridge.driver`, or
   `.command` installer internals.
3. Final DMG is signed, notarized, stapled, validated, and Gatekeeper-assessed
   after contents are final.
4. A mounted-DMG layout verifier fails on the old three-item folder contents.
5. DMG and checksum bytes are generated after final stapling only.

### Phase 48: Install, Upgrade, and Uninstall Proof

**Goal:** Prove the final mounted artifact installs, upgrades, and uninstalls
cleanly with current app/helper/HAL state.

**Requirements:** INST-01, INST-02, INST-03, INST-04, INST-05

**Success criteria:**
1. Release validation installs from the final mounted DMG/PKG path, not
   repo-local build output.
2. Installed app, embedded helper, and HAL driver match the release build
   identity after install.
3. `verify-installed-sync.sh`, `verify-hal-driver.sh`, and
   `apm44-bridge --shm-status` pass or a blocker is recorded before publication.
4. Upgrade over the current latest public release replaces stale installed
   app/helper/driver state.
5. Uninstall guidance or tooling is verified and does not leave stale public
   release claims.

### Phase 49: Public Docs and Release Hygiene Gate

**Goal:** Align public docs with the PKG flow and make release automation fail
closed before publication.

**Requirements:** DOC-01, DOC-02, DOC-03, DOC-04, REL-01, REL-02

**Success criteria:**
1. Public docs describe PKG-primary install, admin prompt, HAL driver location,
   Core Audio reload/reboot caveat, uninstall, and first-run checks.
2. Maintainer release docs and checklists match the new PKG-in-DMG artifact
   sequence and no longer call PKG maintainer-only.
3. README, release notes, and GitHub text stay honest about Cubase 15 /
   USB-C AirPods Max validation and remaining operator caveats.
4. Public tree hygiene checks prove `.planning/`, `.DS_Store`, private keys,
   certificate material, notary logs, and local artifacts are untracked.
5. Full local CI and secret scans pass from a clean release candidate.
6. Release automation fails closed for every signing, notary, stapling,
   checksum, layout, install, installed-sync, and HAL proof gate.

### Phase 50: Latest Release Publication Closure

**Goal:** Publish the clean release to GitHub and reverify the public downloaded
assets.

**Requirements:** REL-03, REL-04, REL-05

**Success criteria:**
1. Final artifacts are produced from a clean commit/tag with non-dirty version
   identity and recorded checksums.
2. GitHub latest release title, notes, assets, checksums, tag, and source
   commit match the validated artifact.
3. Published GitHub assets are downloaded and rechecked for checksum,
   signature/notary state, DMG layout, and release provenance.
4. README/latest-release links resolve to the intended GitHub release.
5. Final local and GitHub checks are recorded before declaring v1.2 shipped.

## Verification Gates

- `bash scripts/ci.sh`
- `bash scripts/check-secrets.sh`
- `pkgutil --check-signature build/signing/APM44Bridge-<version>.pkg`
- `spctl --assess --type install --verbose=4 build/signing/APM44Bridge-<version>.pkg`
- `xcrun stapler validate build/signing/APM44Bridge-<version>.pkg`
- `xcrun stapler validate build/signing/APM44Bridge-<version>.dmg`
- `spctl --assess --type open --context context:primary-signature --verbose=4 build/signing/APM44Bridge-<version>.dmg`
- Mounted-DMG layout verification for PKG-first visible contents.
- Install from the final mounted DMG/PKG.
- `APM44_APP_PATH="/Applications/APM44 Bridge.app" bash scripts/verify-installed-sync.sh`
- `bash scripts/verify-hal-driver.sh`
- `build/BridgeDaemon/apm44-bridge --shm-status`
- `git ls-files` public hygiene check for `.planning/`, `.DS_Store`, keys,
  certificate material, notary logs, and local signing artifacts.
- `gh repo view`, `gh release list`, `gh release view`, GitHub asset download,
  checksum verification, and post-publication signature/notary/layout proof.

## Next Step

Plan Phase 46:

`$gsd-plan-phase 46`

---
*Last updated: 2026-07-01 after v1.2 roadmap creation*
