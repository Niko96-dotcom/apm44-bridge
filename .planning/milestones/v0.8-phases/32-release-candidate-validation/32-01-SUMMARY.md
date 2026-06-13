---
phase: 32-release-candidate-validation
plan: 01
subsystem: release-validation
tags: [ci, release, validation]
key-files:
  created:
    - .planning/phases/32-release-candidate-validation/32-01-SUMMARY.md
  modified:
    - docs/release-validation.md
requirements-completed: [QA-01, QA-02, QA-03]
completed: 2026-06-13
---

# Phase 32 Plan 01 Summary: Release Candidate Validation Closure

## Accomplishments

- Added release-Mac validation commands to `docs/release-validation.md` for secrets, CI, signing, notarization, stapling, Gatekeeper assessment, HAL verification, installed app/helper sync, and shm status.
- Added target-hardware operator validation expectations for clean DMG install, HAL device visibility, menu-bar app start, Cubase route, smoke/soak, and export-rate proof.
- Ran the full local CI gate after all v0.8 changes.

## Verification

```bash
bash scripts/ci.sh
```

Result: passed.

Key evidence:

- `check-secrets: OK (1211 tracked/non-ignored files scanned)`
- Native tests: `100% tests passed, 0 tests failed out of 19`
- Release script tests: `release script tests: OK`
- Swift tests: `Executed 47 tests, with 0 failures`
- Installed-sync dry run: repo/helper IDs matched `0.1.1+c7fbab15782c-dirty`
- Final marker: `ci: OK`
