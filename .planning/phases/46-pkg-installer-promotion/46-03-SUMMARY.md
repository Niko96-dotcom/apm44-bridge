---
phase: 46-pkg-installer-promotion
plan: 03
subsystem: release
tags: [release-all, pkg, dmg, notarization, orchestration]
requires:
  - phase: 46-pkg-installer-promotion
    provides: signed and fully validated package build/notary scripts
provides:
  - mandatory PKG build/notary gate in normal notary-ready release flow
  - local-only unnotarized flow that explicitly skips public PKG claims
affects: [phase-47-dmg-wrapper, phase-49-release-hygiene, phase-50-publication]
tech-stack:
  added: []
  patterns: [release-all order regression for package before final DMG]
key-files:
  created: []
  modified: [scripts/release-all.sh, tests/test_release_scripts.sh]
key-decisions:
  - "APM44_BUILD_PKG is obsolete for public release mode; package validation is mandatory in the notary-ready path."
patterns-established:
  - "Release orchestration tests assert driver staple validation before PKG build, PKG validation before final DMG wrapping, and final DMG notarization last."
requirements-completed: [PKG-01, PKG-02, PKG-03, PKG-04]
duration: 14min
completed: 2026-07-01
---

# Phase 46 Plan 03 Summary

**Mandatory public PKG gate inside the normal release-all path**

## Performance

- **Duration:** 14 min
- **Started:** 2026-07-01T11:02:00Z
- **Completed:** 2026-07-01T11:08:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `run_release_all_pkg_gate_sequence` to prove package build/notarization happens without an opt-in flag.
- Moved PKG build and validation into the normal `NOTARY_READY=1` release flow after app/driver stapling and before final DMG packaging.
- Removed the old `SKIP pkg` public-release branch and added a local-only unnotarized skip message.

## Task Commits

1. **Mandatory release-all package gate** - `ee932d6`

## Files Created/Modified

- `scripts/release-all.sh` - mandatory package gate and artifact listing updates.
- `tests/test_release_scripts.sh` - release orchestration order checks.

## Decisions Made

The public release flow now treats the PKG as a first-class gate before the final DMG wrapper work, while local-only unnotarized builds remain explicit and non-public.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

The red test showed the previous normal release path skipped directly from driver stapling to DMG packaging. The script was updated to add the package gate in that gap.

## User Setup Required

None for automated validation. Real public release still requires signing and notary credentials.

## Next Phase Readiness

Phase 47 can consume `release-all.sh` as a PKG-producing release path before it changes the DMG presentation.

---
*Phase: 46-pkg-installer-promotion*
*Completed: 2026-07-01*
