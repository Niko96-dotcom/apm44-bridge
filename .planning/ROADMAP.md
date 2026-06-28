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
- Active **v1.1 Open Source Release Confidence** - Phases 42-45

## Current Status

v1.1 is in planning. It adds one user-facing feature, a visible Quit control,
then performs the public open-source and release-hygiene pass required before
promoting a new latest GitHub release.

## Phase Numbering

Phase numbering continues from shipped history:

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

## Active Milestone: v1.1 Open Source Release Confidence

| Phase | Name | Goal | Requirements |
|-------|------|------|--------------|
| 42 | App Quit Control | Add a visible, graceful Quit control to the app UI. | QUIT-01, QUIT-02, QUIT-03, QUIT-04 |
| 43 | Public Repository Surface | Make public docs, metadata, templates, and open-source posture accurate. | PUB-01, PUB-02, PUB-03, PUB-04 |
| 44 | Security and Release Hygiene Gate | Prove secrets, public safety, CI, installed sync, and artifact validation before publication. | SEC-01, SEC-02, SEC-03, SEC-04, REL-01, REL-02, REL-03 |
| 45 | Latest Release Publication Closure | Publish or update the latest GitHub release and verify the public result. | REL-04, REL-05 |

### Phase 42: App Quit Control

**Goal:** Add a visible app UI control that closes APM44 Bridge gracefully.

**Requirements:** QUIT-01, QUIT-02, QUIT-03, QUIT-04

**Success criteria:**
1. App UI exposes a clear Quit control in the existing app surface.
2. Quit delegates to existing lifecycle/process-management ownership rather
   than duplicating daemon kill logic in the UI layer.
3. Quit does not uninstall, reload, or mutate the HAL driver.
4. Automated and/or manual app-run evidence proves the Quit path exits cleanly.

### Phase 43: Public Repository Surface

**Goal:** Make the repository look and read like a professional open-source
macOS audio utility.

**Requirements:** PUB-01, PUB-02, PUB-03, PUB-04

**Success criteria:**
1. README, docs, repo description, homepage, and release links agree on current
   product behavior and artifact truth.
2. License, SECURITY, CONTRIBUTING, support expectations, and issue templates
   are present and accurate.
3. Install, uninstall, troubleshooting, permissions, HAL behavior, and caveats
   are documented for public users.
4. Public tree review confirms private planning/internal artifacts stay out of
   the public repository.

### Phase 44: Security and Release Hygiene Gate

**Goal:** Run the professional release gate before publishing anything new.

**Requirements:** SEC-01, SEC-02, SEC-03, SEC-04, REL-01, REL-02, REL-03

**Success criteria:**
1. Secret/private-artifact scans pass for the current release candidate.
2. Full local CI passes, including native tests, Swift tests, release-script
   regressions, app embed, and installed-sync dry-run.
3. Installed app/helper/driver identity proof is captured before claiming the
   running installed version is current.
4. Signed/notarized/stapled/Gatekeeper artifact evidence and checksums are
   captured, or publication is blocked with a clear reason.
5. GitHub repo/profile security and metadata review finds no private or
   misleading public claims.

### Phase 45: Latest Release Publication Closure

**Goal:** Promote the latest GitHub release only after the release gate passes,
then verify the public result.

**Requirements:** REL-04, REL-05

**Success criteria:**
1. GitHub release tag, title, notes, assets, checksums, and latest status match
   the validated artifact.
2. README/latest-release links resolve to the intended GitHub release.
3. Release notes document target Cubase 15 / USB-C AirPods Max validation and
   any remaining operator-dependent caveats.
4. Final local and GitHub checks are recorded before declaring the milestone
   ready to ship.

## Verification Gates

- `scripts/ci.sh`
- `scripts/check-secrets.sh`
- `scripts/verify-installed-sync.sh --dry-run`
- `APM44_APP_PATH="/Applications/APM44 Bridge.app" ./scripts/verify-installed-sync.sh`
- `bash scripts/verify-hal-driver.sh`
- `apm44-bridge --shm-status`
- Developer ID signing, notarization, stapling, Gatekeeper validation, and
  checksum verification for the public DMG.
- `gh repo view`, `gh release list`, and post-publication latest-release asset
  verification.

## Next Step

Plan Phase 42:

`$gsd-plan-phase 42`

---
*Last updated: 2026-06-28 after v1.1 roadmap creation*
