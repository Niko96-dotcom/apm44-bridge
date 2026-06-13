---
phase: 28-strict-verification-and-runtime-guards
plan: 01
subsystem: release-verification
tags: [codesign, release, security, scripts]
provides:
  - Strict Hardened Runtime release verification
  - Strict Developer ID Application release verification
  - Explicit local codesign override
key-files:
  created:
    - .planning/phases/28-strict-verification-and-runtime-guards/28-01-SUMMARY.md
  modified:
    - scripts/codesign-verify-release.sh
    - tests/test_release_scripts.sh
requirements-completed: [REL-01, REL-02]
completed: 2026-06-13
---

# Phase 28 Plan 01 Summary: Strict Codesign Verification

## Accomplishments

- Changed `scripts/codesign-verify-release.sh` so missing Hardened Runtime is a failure by default.
- Changed the same script so missing Developer ID Application identity is a failure by default.
- Added `APM44_ALLOW_LOCAL_CODESIGN=1` as the explicit local-development override for ad-hoc/non-runtime checks.
- Added fake `codesign` fixtures and regression cases for strict pass, missing runtime failure, missing Developer ID failure, and local override success.

## Verification

```bash
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Result: passed.
