---
phase: 06-hal-signing-load-verification
plan: 01
subsystem: infra
tags: [codesign, notarization, hal, release]
requires:
  - phase: v1.0-phases-04
    provides: APM44Bridge.driver bundle
provides:
  - sign-release.sh
  - notary-dry-run.sh
  - codesign-verify-release.sh
  - CI workflow_dispatch stub
affects: [phase-10-product-distribution]
tech-stack:
  added: []
  patterns: ["Developer ID + Hardened Runtime on all three artifacts"]
key-files:
  created: [scripts/sign-release.sh, scripts/notary-dry-run.sh, scripts/codesign-verify-release.sh, .github/workflows/sign-notarize.yml]
  modified: [scripts/verify-hal-driver.sh, docs/release.md]
key-decisions:
  - "Signing identity is supplied by maintainer environment on the sign-off Mac"
  - "CI sign-notarize is workflow_dispatch only until APPLE_SIGN_ID secret exists"
requirements-completed: [SHIP-01, SHIP-02, SHIP-03, DEV-01]
duration: 15min
completed: 2026-06-01
---

# Phase 6 Plan 01 Summary

**Release signing scripts with Developer ID defaults, notary dry-run zip workflow, and HAL verify enhancements for macOS 15+ load.**

## Task Commits

1. **Release signing scripts** - `a47e3ac`

## Self-Check: PASSED

- FOUND: scripts/sign-release.sh
- FOUND: commit a47e3ac

## Deviations from Plan

None — plan executed inline during autonomous run.

## Human follow-up

- Run `bash scripts/sign-release.sh` and `bash scripts/notary-dry-run.sh` on sign-off Mac with AC_NOTARY profile
- Capture notary submission ID for SHIP-02 evidence
