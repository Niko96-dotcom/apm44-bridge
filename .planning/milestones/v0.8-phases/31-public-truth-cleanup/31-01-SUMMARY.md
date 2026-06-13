---
phase: 31-public-truth-cleanup
plan: 01
subsystem: release-docs
tags: [docs, release, latency]
key-files:
  created:
    - .planning/phases/31-public-truth-cleanup/31-01-SUMMARY.md
  modified:
    - docs/install.md
    - docs/release.md
    - docs/release-validation.md
    - .github/workflows/release.yml
    - .github/workflows/sign-notarize.yml
requirements-completed: [DOC-01, DOC-02]
completed: 2026-06-13
---

# Phase 31 Plan 01 Summary: Release Docs Truth Cleanup

## Accomplishments

- Replaced stale v0.4 release-posture language with current release-candidate/v0.8 wording.
- Kept the public artifact story centered on current `APM44Bridge-0.1.1.dmg`.
- Updated release validation commands to use `APM44_VERSION:-0.1.1` so docs and scripts share the same version default.
- Confirmed install docs still describe Safe as the long-session/default-friendly latency choice.

## Verification

```bash
rg -n "v0\\.4|APM44Bridge-0\\.1\\.1\\.dmg" README.md docs .github
```

Result: passed with only intentional current artifact references.
