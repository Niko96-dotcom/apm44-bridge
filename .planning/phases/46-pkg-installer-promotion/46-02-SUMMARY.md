---
phase: 46-pkg-installer-promotion
plan: 02
subsystem: release
tags: [pkg, notarization, stapler, gatekeeper, checksum]
requires:
  - phase: 46-pkg-installer-promotion
    provides: fail-closed signed package output from plan 01
provides:
  - package signature validation before and after stapling
  - Gatekeeper installer assessment for public PKG bytes
  - final-byte package checksum generation after validation
affects: [release-all, phase-47-dmg-wrapper, phase-50-publication]
tech-stack:
  added: []
  patterns: [post-staple checksum generation, package-byte validation order tests]
key-files:
  created: []
  modified: [scripts/notarize-release-pkg.sh, tests/test_release_scripts.sh]
key-decisions:
  - "The notarization gate validates the actual package signature with pkgutil instead of inferring readiness from Keychain identities."
patterns-established:
  - "Final package checksum is written only after notary acceptance, stapling, final signature validation, and spctl assessment."
requirements-completed: [PKG-02, PKG-03, PKG-04]
duration: 18min
completed: 2026-07-01
---

# Phase 46 Plan 02 Summary

**Notarized PKG byte validation with Gatekeeper assessment and final checksum**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-01T10:52:00Z
- **Completed:** 2026-07-01T11:02:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added release-script regression coverage for package notarization order and rejected-notary checksum absence.
- Replaced Keychain identity inference in `notarize-release-pkg.sh` with `pkgutil --check-signature "$PKG"` validation.
- Added final `spctl --assess --type install --verbose=4 "$PKG"` and `$PKG.sha256` generation after all package validations pass.

## Task Commits

1. **Package validation order and checksum gate** - `40bfb50`

## Files Created/Modified

- `scripts/notarize-release-pkg.sh` - signature checks, Gatekeeper assessment, and post-staple checksum.
- `tests/test_release_scripts.sh` - `run_pkg_validation_order_check` and fake `pkgutil`/`spctl` validation.

## Decisions Made

Package readiness is proven from the package file itself, not from whatever identities are present in the maintainer Keychain at notarization time.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

The first red test confirmed the previous script stapled the package but did not run `pkgutil`, `spctl`, or checksum creation. The production script was then updated to make the test pass.

## User Setup Required

None for automated validation. Real notarization still requires the release Mac notary profile.

## Next Phase Readiness

Plan 03 can call `scripts/notarize-release-pkg.sh` as a complete public package validation gate.

---
*Phase: 46-pkg-installer-promotion*
*Completed: 2026-07-01*
