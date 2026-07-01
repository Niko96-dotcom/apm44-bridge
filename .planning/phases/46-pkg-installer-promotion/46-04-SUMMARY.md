---
phase: 46-pkg-installer-promotion
plan: 04
subsystem: release
tags: [pkg, install-scripts, provenance, installed-sync, hal]
requires:
  - phase: 46-pkg-installer-promotion
    provides: mandatory validated public PKG gate
provides:
  - explicit PKG preinstall stale app/driver replacement semantics
  - non-destructive package verifier with payload, script, checksum, signature, notary, and Gatekeeper checks
  - package provenance with package, git, helper, app bundle, and driver executable identity
affects: [phase-47-dmg-wrapper, phase-48-install-proof, phase-50-publication]
tech-stack:
  added: []
  patterns: [package verifier default non-destructive mode, explicit install-smoke opt-in]
key-files:
  created: [scripts/verify-release-pkg.sh]
  modified: [scripts/build-release-pkg.sh, docs/release-validation.md, tests/test_release_scripts.sh]
key-decisions:
  - "Phase 46 proves package handoff and optional install smoke, while Phase 48 still owns final mounted DMG/PKG install proof."
  - "Verifier fixture paths are injectable so release-script tests do not contaminate real build artifacts."
patterns-established:
  - "APM44_RUN_PKG_INSTALL_SMOKE=1 is required before verifier writes /Applications or HAL paths."
requirements-completed: [PKG-01, PKG-04, PKG-05]
duration: 36min
completed: 2026-07-01
---

# Phase 46 Plan 04 Summary

**Package replacement scripts and release PKG verifier with deterministic provenance**

## Performance

- **Duration:** 36 min
- **Started:** 2026-07-01T11:08:00Z
- **Completed:** 2026-07-01T11:11:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added PKG `preinstall` stale app/driver removal and postinstall required-path checks.
- Added `scripts/verify-release-pkg.sh` for non-destructive package signature, stapled ticket, Gatekeeper, checksum, payload, install-script, and provenance verification.
- Documented the `## PKG-primary package gate` flow and explicit `APM44_RUN_PKG_INSTALL_SMOKE=1` install smoke.
- Isolated verifier tests from real build artifacts after full CI revealed a fake daemon contamination risk.

## Task Commits

1. **Replacement install target semantics** - `246f651`
2. **Release PKG verifier and docs** - `3558d1b`
3. **Verifier fixture isolation** - `717d9e1`

## Files Created/Modified

- `scripts/build-release-pkg.sh` - `preinstall` and postinstall installed-path checks.
- `scripts/verify-release-pkg.sh` - package verifier and provenance writer.
- `docs/release-validation.md` - PKG-primary package gate and install-smoke commands.
- `tests/test_release_scripts.sh` - replacement-script and verifier regression coverage.

## Decisions Made

The default verifier is intentionally non-destructive. Install smoke must be explicit because it writes `/Applications/APM44 Bridge.app` and `/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver`.

## Deviations from Plan

### Auto-fixed Issues

**1. Test fixture contaminated real build daemon**
- **Found during:** Full CI after initial verifier implementation
- **Issue:** `run_verify_release_pkg_check` wrote a fake `build/BridgeDaemon/apm44-bridge`, causing installed-sync dry-run to report `FAKEPKG123`.
- **Fix:** Added verifier env overrides and moved test app/driver/daemon fixtures into `$TMP`.
- **Verification:** `bash tests/test_release_scripts.sh`; full `bash scripts/ci.sh` rerun ended with real `repo_build_id=0.11.1+717d9e16ec0a` and `ci: OK`.
- **Committed in:** `717d9e1`

## Issues Encountered

The first full CI run passed but showed the fake build ID in installed-sync output. That was treated as invalid evidence until fixture isolation was fixed and CI was rerun cleanly.

## User Setup Required

None for automated validation. Running `APM44_RUN_PKG_INSTALL_SMOKE=1 bash scripts/verify-release-pkg.sh` requires admin install authorization and is intentionally deferred to Phase 48 final mounted-artifact proof.

## Next Phase Readiness

Phase 47 can wrap the validated package into a professional DMG, and Phase 48 can use `scripts/verify-release-pkg.sh` plus install-smoke mode for final install proof.

---
*Phase: 46-pkg-installer-promotion*
*Completed: 2026-07-01*
