# Phase 5 verification: Integration & Ship Readiness

**Date:** 2026-06-01  
**Overall status:** `passed` (automated docs/scripts); `human_needed` (DAW matrix, export bounce, signing dry-run)

## Automated checks

| Check | Status | Notes |
|-------|--------|-------|
| `cmake --build build` | passed | Release/Debug build tree |
| `ctest --test-dir build --output-on-failure` | passed | 9/9 tests |
| `bash scripts/validate-export-rate.sh --instructions` | passed | QA-02 workflow documented |
| `bash scripts/validate-export-rate.sh --help` | passed | CLI contract |
| `bash -n scripts/install-driver.sh` | passed | Syntax OK; driver bundle pending Phase 4 |
| `test -f docs/daw-matrix.md` | passed | Logic + Ableton matrix |
| `test -f docs/release.md` | passed | codesign + notarytool |
| `test -f Driver/APM44Bridge.entitlements` | passed | HAL entitlements template |
| README links to phase 5 docs | passed | daw-matrix, release, validate script |

## Hardware / account-dependent checks

| Check | Status | Notes |
|-------|--------|-------|
| Logic Pro matrix rows (monitoring + 30+ min) | human_needed | `docs/daw-matrix.md` |
| Ableton Live matrix rows | human_needed | same |
| QA-02 bounce → `--check-file` @ 44100 Hz | human_needed | `scripts/validate-export-rate.sh` |
| Developer ID sign + notarytool dry-run | human_needed | `docs/release.md`; needs Apple Developer creds |
| Production path (APM44 Bridge device) | pending | Phase 4 HAL driver not built yet |
| MVP path (BlackHole) full sign-off | human_needed | Can run now on hardware |

## Requirements traceability

| ID | Status | Evidence |
|----|--------|----------|
| QA-02 | passed (automated doc/script) / human_needed (bounce) | `validate-export-rate.sh`, `daw-matrix.md` export rows |

## ROADMAP Phase 5 success criteria

| Criterion | Status |
|-----------|--------|
| Export/stem remains 44100 when project is 44100 | human_needed (script + doc ready) |
| E2E DAW → bridge → AirPods 30+ min | human_needed | refs `soak-test.md`, `daw-matrix.md` |
| DAW matrix Logic + Ableton | human_needed | checklist shipped |
| Developer ID signed artifacts ready for notarization test | human_needed | `release.md` + entitlements |

## Commit references

| Plan | Commit |
|------|--------|
| 05-01 Task 1 | (pending) |
| 05-01 Task 2 | (pending) |
| 05-01 Task 3 | (pending) |

## Gaps / deferred

- Phase 4 `APM44Bridge.driver` not in tree — production matrix column marked pending
- GitHub Actions macOS CI job optional (compile-only) — not added this plan
- Hardware matrix and notarization remain manual per CONTEXT

## Checkpoint note

Execution used `--no-transition`: human UAT and notarization dry-run documented as `human_needed`; no blocking checkpoint pause.
