---
phase: 47-professional-dmg-presentation
plan: 01
subsystem: release
tags: [dmg, pkg-first, layout, gatekeeper, release-all]
requires:
  - phase: 46-pkg-installer-promotion
    provides: signed, notarized, Gatekeeper-assessed PKG output
provides:
  - final package-only DMG staging with top-level PKG and README
  - DMG layout verifier rejecting raw app, HAL driver, and command installer internals
  - DMG Gatekeeper assessment before checksum generation
affects: [phase-48-install-proof, phase-49-docs-release-hygiene, phase-50-publication]
tech-stack:
  added: []
  patterns: [PKG-first DMG layout verification, post-staple DMG assessment before checksum]
key-files:
  created: [scripts/verify-release-dmg-layout.sh]
  modified: [scripts/build-release-dmg.sh, scripts/release-all.sh, scripts/notarize-release-dmg.sh, tests/test_release_scripts.sh, docs/release-validation.md]
key-decisions:
  - "The final public DMG exposes the validated PKG and README only; raw app/driver/command contents remain limited to non-final staging."
patterns-established:
  - "release-all verifies final DMG layout before notarizing the public DMG."
requirements-completed: [DMG-01, DMG-02, DMG-03, DMG-04, DMG-05]
duration: 25min
completed: 2026-07-01
---

# Phase 47 Plan 01 Summary

**PKG-first final DMG layout with automated layout and Gatekeeper gates**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-01T11:18:00Z
- **Completed:** 2026-07-01T11:27:00Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Changed `APM44_DMG_PACKAGE_ONLY=1` packaging so the final DMG stages the validated `.pkg` plus `README.txt`, excluding raw app, HAL driver, and command installer internals.
- Added `scripts/verify-release-dmg-layout.sh` with staging and mounted-DMG inspection modes.
- Wired layout verification into `scripts/release-all.sh` between package-only DMG creation and DMG notarization.
- Added DMG `spctl --assess --type open --context context:primary-signature --verbose=4` before final checksum creation.

## Task Commits

1. **PKG-first final DMG and layout gate** - `8484ec4`

## Files Created/Modified

- `scripts/build-release-dmg.sh` - package-only mode now stages PKG-first public contents.
- `scripts/verify-release-dmg-layout.sh` - layout verifier for staging or mounted DMG.
- `scripts/release-all.sh` - layout gate before DMG notarization.
- `scripts/notarize-release-dmg.sh` - Gatekeeper assessment before checksum.
- `tests/test_release_scripts.sh` - fake `hdiutil`, PKG-first layout tests, layout verifier tests, and release-all order checks.
- `docs/release-validation.md` - added layout verifier command.

## Decisions Made

The final public DMG should have a single obvious installer object. Raw internals stay out of the public presentation and are rejected by an automated layout check.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

The initial bad-layout fixture lacked a PKG, so the verifier failed on missing package before reaching the raw-internals assertion. The fixture was adjusted to include a PKG and README so it specifically proves raw app/driver/command rejection.

## User Setup Required

None for automated validation. Real mounted-DMG install proof remains Phase 48.

## Next Phase Readiness

Phase 48 can install from a final mounted DMG whose visible contents are the validated PKG-first layout.

---
*Phase: 47-professional-dmg-presentation*
*Completed: 2026-07-01*
