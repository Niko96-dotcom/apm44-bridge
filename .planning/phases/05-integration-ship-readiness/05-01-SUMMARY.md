---
phase: 05-integration-ship-readiness
plan: 01
subsystem: testing
tags: [daw-matrix, codesign, notarytool, qa-02, release]
requires:
  - phase: 03-menu-bar-application
    provides: menu bar app and verify-menu-bar.sh
provides:
  - DAW validation matrix for Logic and Ableton
  - Export rate validation script (QA-02)
  - Release signing and notarization documentation
  - HAL driver entitlements and dev install script
affects: [phase-4-hal-virtual-device]
tech-stack:
  added: [afinfo export check, notarytool dry-run docs]
  patterns: [MVP vs production matrix columns, ad-hoc HAL dev install]
key-files:
  created:
    - docs/daw-matrix.md
    - docs/release.md
    - scripts/validate-export-rate.sh
    - scripts/install-driver.sh
    - Driver/APM44Bridge.entitlements
    - .planning/phases/05-integration-ship-readiness/05-01-PLAN.md
    - .planning/phases/05-integration-ship-readiness/05-VERIFICATION.md
  modified:
    - README.md
key-decisions:
  - "CI stays build+ctest+offline soak; DAW matrix and notarization manual"
  - "Production matrix column pending until Phase 4 HAL driver ships"
requirements-completed: []
duration: 15min
completed: 2026-06-01
---

# Phase 5 Plan 01: Integration & Ship Readiness Summary

**DAW validation matrix, QA-02 export-rate script, and Developer ID / notarytool release guide with HAL entitlements.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-06-01T12:00:00Z
- **Completed:** 2026-06-01T12:15:00Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Logic + Ableton DAW matrix with pass/fail columns (MVP BlackHole + production APM44 Bridge column)
- `validate-export-rate.sh` for bounce instructions and `afinfo` sample-rate check
- `release.md` covering codesign, notarytool submit/staple, ad-hoc dev install
- README refreshed with phase status and documentation index

## Task Commits

1. **Task 1: DAW matrix and export-rate validation script** - `fc7f08e` (docs)
2. **Task 2: Release signing docs and entitlements** - `7269ee0` (docs)
3. **Task 3: README, verification report, summaries** - `c4c49d9` (docs)

**Plan metadata:** `TBD` (final docs commit)

## Files Created/Modified

- `docs/daw-matrix.md` - Full-stack DAW checklist
- `scripts/validate-export-rate.sh` - QA-02 helper
- `docs/release.md` - Distribution signing guide
- `Driver/APM44Bridge.entitlements` - HAL plug-in entitlements template
- `scripts/install-driver.sh` - Ad-hoc dev driver install
- `README.md` - Phase table and doc links
- `.planning/phases/05-integration-ship-readiness/05-VERIFICATION.md` - Automated vs human gates

## Decisions Made

- Hardware DAW matrix and notarization dry-run remain manual; CI limited to compile/test/soak
- Production path rows in matrix deferred until Phase 4 driver exists

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

- Apple Developer Program + notarytool credentials for signing dry-run (`docs/release.md`)
- Logic/Ableton hardware runs for matrix sign-off (`docs/daw-matrix.md`)

## Next Phase Readiness

- Phase 4 HAL driver can use `Driver/APM44Bridge.entitlements` and `install-driver.sh`
- Producer can run MVP matrix on BlackHole path now; production column after Phase 4

## Self-Check: PASSED

- FOUND: docs/daw-matrix.md
- FOUND: docs/release.md
- FOUND: scripts/validate-export-rate.sh
- FOUND: scripts/install-driver.sh
- FOUND: Driver/APM44Bridge.entitlements
- FOUND: .planning/phases/05-integration-ship-readiness/05-VERIFICATION.md
- FOUND: fc7f08e, 7269ee0, c4c49d9

---
*Phase: 05-integration-ship-readiness*
*Completed: 2026-06-01*
