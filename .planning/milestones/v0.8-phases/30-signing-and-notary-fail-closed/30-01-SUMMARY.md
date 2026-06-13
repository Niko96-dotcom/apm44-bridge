---
phase: 30-signing-and-notary-fail-closed
plan: 01
subsystem: signing-workflow
tags: [github-actions, release, signing]
key-files:
  created:
    - .planning/phases/30-signing-and-notary-fail-closed/30-01-SUMMARY.md
  modified:
    - .github/workflows/sign-notarize.yml
    - tests/test_release_scripts.sh
requirements-completed: [SIGN-01, SIGN-02, SIGN-03, SIGN-04]
completed: 2026-06-13
---

# Phase 30 Plan 01 Summary: Signing Workflow Fail-Closed Coverage

## Accomplishments

- Updated `.github/workflows/sign-notarize.yml` so the Release build step builds both `apm44-bridge` and `APM44Bridge`.
- Changed missing `APPLE_SIGN_ID` and missing `AC_NOTARY` handling from successful skips to explicit workflow errors.
- Added release-script regression assertions for the build target and fail-closed credential messages.

## Verification

```bash
bash tests/test_release_scripts.sh
```

Result: passed.
