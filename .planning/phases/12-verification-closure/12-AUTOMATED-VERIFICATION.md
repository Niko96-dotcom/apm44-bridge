---
phase: 12
plan: 01
title: Automated verification (CI gates)
date: 2026-06-12
command: bash scripts/ci.sh
status: pass
---

# Phase 12 — Automated Verification

This artifact is the QA-01 / QA-02 evidence: the full
`scripts/ci.sh` run on a non-hardware dev machine, with the
newly-added `verify-installed-sync.sh --dry-run` step.

Full stdout/stderr is in `12-ci-run.log` (same directory).

## CI steps and results

| Step | Status | Notes |
| --- | --- | --- |
| Secret scan | PASS | `scripts/check-secrets.sh` clean. |
| Prepare submodules | PASS | Catch2 + libsamplerate fetched. |
| Configure CMake (Release) | PASS | No errors. |
| Build native targets | PASS | All targets built, including `apm44-hal-smoke`, `apm44-soak`, and the 20 ctest binaries. |
| Native tests (ctest) | PASS | `100% tests passed, 0 tests failed out of 20`. |
| Swift app build (xcodegen + xcodebuild) | PASS | `** BUILD SUCCEEDED **`. |
| Swift unit tests (xcodebuild test) | PASS | `42 tests, with 0 failures`. |
| Installed-sync dry-run | PASS | `OK: repo and embedded helper match (0.1.1+4fd2f6d43cf7-dirty)`. |
| Final `ci: OK` | PASS | Script exits 0. |

## Test summary

- **ctest:** 20/20 passed (15 from v0.2 + 5 new from phase 11
  SHM-validation tests).
- **xcodebuild test:** 42/42 passed (no regressions in
  `DeviceCatalogTests`, `HalDriverDetectorTests`,
  `LatencyPresetTests`, `MetricsParserTests`,
  `BridgeProcessManagerTests`, etc.).

## Deviations

None. The first CI run (after the dry-run was added but before
re-embedding the helper) caught a real build-ID drift between
the repo daemon and the embedded helper — this was the exact
class of drift the dry-run is meant to surface. After
`scripts/embed-daemon-in-app.sh` re-embedded the daemon, the
helper ID matched the repo ID, and CI went green.

## Verification

- Full log: `12-ci-run.log`
- This artifact satisfies QA-01 (`ci.sh` includes the
  non-hardware dry-run) and QA-02 (the full gate covers
  secret scan, CMake/Catch2 tests, Swift app build/tests, and
  the installed-sync dry-run).
- Live installed-system evidence (QA-03, QA-04) is captured
  in `12-LIVE-VERIFICATION.md`.
