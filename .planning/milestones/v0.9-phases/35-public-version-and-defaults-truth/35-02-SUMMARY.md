---
phase: 35-public-version-and-defaults-truth
plan: 02
subsystem: public-doc-truth
tags: [docs, latency, release]
key-files:
  created:
    - .planning/phases/35-public-version-and-defaults-truth/35-02-SUMMARY.md
  modified:
    - docs/install.md
    - docs/menu-bar-qa.md
    - docs/release.md
    - tests/test_release_scripts.sh
requirements-completed: [DOC-02, DOC-03]
completed: 2026-06-14
---

# Phase 35 Plan 02 Summary: Defaults and Driver Path Truth

## Accomplishments

- Updated install docs to say Safe is the fresh-install default and Balanced is a lower-latency option after setup.
- Updated menu-bar QA to expect Safe as the fresh-install default.
- Replaced stale `build/Release/APM44Bridge.driver` references in release docs with `build/Driver/APM44Bridge.driver`.
- Extended release-script doc guards to fail if stale Balanced-default or wrong driver path wording returns.

## Verification

```bash
bash tests/test_release_scripts.sh
```

Result: passed.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED
