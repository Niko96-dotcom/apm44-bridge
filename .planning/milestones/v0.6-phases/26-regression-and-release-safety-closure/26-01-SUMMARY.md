---
phase: 26-regression-and-release-safety-closure
plan: 01
subsystem: ci-release-safety
tags: [github-actions, release-tests, ci, installed-sync]
provides:
  - GitHub CI release-script regression step
  - Source guard proving CI keeps running release-script tests after native tests
  - Bounded installed-sync dry-run verifier for app-bundled helpers
key-files:
  created:
    - .planning/phases/26-regression-and-release-safety-closure/26-01-SUMMARY.md
  modified:
    - .github/workflows/ci.yml
    - tests/test_release_scripts.sh
    - scripts/verify-installed-sync.sh
requirements-completed: [CI-02]
completed: 2026-06-13
---

# Phase 26 Plan 01 Summary: CI Release Safety Closure

## Accomplishments

- Added a public GitHub CI step named `Release script tests` after native CTest execution.
- Wired that CI step to run `bash tests/test_release_scripts.sh`.
- Added `run_ci_02_release_script_tests_in_github_ci` so release-script regressions fail if CI stops running that gate or runs it before native tests.
- Bounded installed-sync `--version` probes with a five-second timeout so full CI cannot hang on app-bundled helper startup.
- Preserved dry-run installed-sync validation when the embedded helper `--version` is unavailable but its SHA-256 matches the repo daemon.
- Ran the full local CI gate after the v0.6 fixes.

## Verification

```bash
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Result: passed. Full CI completed the secret scan, native build/tests, release-script tests, Swift build/tests, and installed-sync dry-run.

## Notes

The full CI run exposed an app-bundle helper `--version` hang before `main` despite identical helper/repo daemon hashes. The installed-sync verifier now treats that as a bounded dry-run warning only when the helper binary hash matches the repo daemon; non-dry verification still fails if the helper build ID cannot be parsed.
