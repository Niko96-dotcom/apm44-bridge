---
phase: 46-pkg-installer-promotion
plan: 01
subsystem: release
tags: [pkg, installer-signing, release-scripts, fail-closed]
requires:
  - phase: 46-pkg-installer-promotion
    provides: smart discuss context, research, validation strategy, and package release plans
provides:
  - fail-closed Developer ID Installer identity resolution
  - signed public package output only when installer identity is valid
  - local-only unsigned package override with non-publishable naming
affects: [release-all, pkg-build, phase-47-dmg-wrapper]
tech-stack:
  added: []
  patterns: [fake release tooling for credential-free package identity tests]
key-files:
  created: []
  modified: [scripts/build-release-pkg.sh, tests/test_release_scripts.sh]
key-decisions:
  - "Public PKG output must fail closed when Developer ID Installer identity is missing, ambiguous, or the wrong certificate class."
  - "Unsigned package bytes may be produced only through APM44_ALLOW_UNSIGNED_PKG=1 and only as local-only non-publishable output."
patterns-established:
  - "Release-script tests model zero, one, multiple, and application-only signing identities."
requirements-completed: [PKG-01, PKG-02, PKG-04]
duration: 52min
completed: 2026-07-01
---

# Phase 46 Plan 01 Summary

**Fail-closed package signing identity resolution for public PKG output**

## Performance

- **Duration:** 52 min
- **Started:** 2026-07-01T10:08:00Z
- **Completed:** 2026-07-01T10:52:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added credential-free release-script coverage for missing, ambiguous, wrong-class, local-only, and valid Developer ID Installer identity states.
- Updated `scripts/build-release-pkg.sh` so public `.pkg` output requires a valid `Developer ID Installer:` identity.
- Preserved a clearly local-only unsigned escape hatch that writes `*-local-unsigned.pkg` and never masquerades as the public package.

## Task Commits

1. **Task 1: Add package identity gate coverage** - `55f5333`
2. **Task 2: Fail closed package identity resolution** - `fcc74f2`
3. **Security hygiene: Redact local signing identity evidence** - `1618535`

## Files Created/Modified

- `scripts/build-release-pkg.sh` - public PKG signing identity resolution and local-only unsigned output handling.
- `tests/test_release_scripts.sh` - fake `security`, `pkgbuild`, `productsign`, and PKG builder identity-gate tests.

## Decisions Made

Developer ID Application certificates are insufficient for public installer packages; the package builder must require the Installer certificate class.

## Deviations from Plan

### Auto-fixed Issues

**1. Planning artifact contained local certificate subject**
- **Found during:** Full CI secret scan
- **Issue:** Tracked research evidence included a real Developer ID subject string.
- **Fix:** Redacted exact local certificate subject from `46-RESEARCH.md`.
- **Verification:** `bash scripts/check-secrets.sh` and later `bash scripts/ci.sh`.
- **Committed in:** `1618535`

## Issues Encountered

The first fake `ditto` implementation did not handle archive-form arguments used by the release scripts. The test fake was extended to support both copy and archive modes.

## User Setup Required

None for automated validation. Public package publication still requires a real Developer ID Installer identity on the release Mac.

## Next Phase Readiness

Plan 02 can assume package bytes at the public `.pkg` path are signed by a Developer ID Installer identity or the builder has failed.

---
*Phase: 46-pkg-installer-promotion*
*Completed: 2026-07-01*
