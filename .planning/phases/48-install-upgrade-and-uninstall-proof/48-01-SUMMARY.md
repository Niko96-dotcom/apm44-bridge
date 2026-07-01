---
phase: 48-install-upgrade-and-uninstall-proof
plan: 01
subsystem: release
tags: [install, mounted-dmg, pkg, uninstall, sudo-gate]
requires:
  - phase: 47-professional-dmg-presentation
    provides: PKG-first final DMG layout
provides:
  - final mounted DMG package source verifier
  - explicit install-smoke gate for installed-sync, HAL verifier, and shm-status
  - dry-run safe uninstall helper with explicit destructive approval
affects: [phase-49-docs-release-hygiene, phase-50-publication]
tech-stack:
  added: []
  patterns: [non-destructive default verification, sudo -n fail-closed destructive gates]
key-files:
  created: [scripts/verify-final-install-artifact.sh, scripts/uninstall-apm44.sh]
  modified: [docs/install.md, docs/release-validation.md, tests/test_release_scripts.sh]
key-decisions:
  - "Destructive install/uninstall proof requires explicit opt-in and non-interactive sudo; this autonomous run records the local sudo blocker truthfully."
patterns-established:
  - "Final-artifact proof must resolve the PKG from the mounted DMG, not repo-local build output."
requirements-completed: [INST-01, INST-02, INST-03, INST-04, INST-05]
duration: 22min
completed: 2026-07-01
---

# Phase 48 Plan 01 Summary

**Mounted-DMG install source verifier and dry-run safe uninstall gate**

## Performance

- **Duration:** 22 min
- **Started:** 2026-07-01T11:28:00Z
- **Completed:** 2026-07-01T11:34:00Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added `scripts/verify-final-install-artifact.sh` to resolve the install source from the final mounted DMG and validate package signature, stapled ticket, and Gatekeeper install assessment.
- Added explicit `APM44_RUN_FINAL_INSTALL_SMOKE=1` install smoke that runs `installer`, installed-sync, HAL verification, and `--shm-status` only after sudo readiness passes.
- Added `scripts/uninstall-apm44.sh`, dry-run by default, with `--yes` required to remove app, HAL driver, receipt, and reload Core Audio.
- Updated release/user docs with final install and uninstall validation commands.

## Task Commits

1. **Final install/uninstall proof gates** - `c890f52`

## Files Created/Modified

- `scripts/verify-final-install-artifact.sh` - mounted final DMG package verifier and install-smoke gate.
- `scripts/uninstall-apm44.sh` - dry-run safe uninstall helper.
- `docs/release-validation.md` - final install smoke and uninstall validation commands.
- `docs/install.md` - PKG install and uninstall guidance.
- `tests/test_release_scripts.sh` - final-artifact verifier and uninstall script regressions.

## Decisions Made

The autonomous run must not prompt for a password or mutate system install locations silently. Local `sudo -n true` failed, so destructive install/uninstall proof is scripted and documented as an explicit operator step.

## Deviations from Plan

None - the plan included the sudo constraint and fail-closed operator gate.

## Issues Encountered

`sudo -n true` returned `sudo: a password is required`, so `APM44_RUN_FINAL_INSTALL_SMOKE=1` and `uninstall-apm44.sh --yes` were not run locally. Non-destructive script behavior and full CI passed.

## User Setup Required

To run the destructive proof on the release Mac:

```bash
APM44_RUN_FINAL_INSTALL_SMOKE=1 bash scripts/verify-final-install-artifact.sh
bash scripts/uninstall-apm44.sh --yes
```

Both require admin authorization or sudo readiness.

## Next Phase Readiness

Phase 49 can align public docs and release automation around the PKG-first DMG, final install verifier, and explicit uninstall path.

---
*Phase: 48-install-upgrade-and-uninstall-proof*
*Completed: 2026-07-01*
