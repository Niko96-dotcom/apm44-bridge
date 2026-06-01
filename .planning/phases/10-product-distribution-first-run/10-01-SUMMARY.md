---
phase: 10-product-distribution-first-run
plan: 01
subsystem: infra
tags: [dmg, pkg, first-run, distribution]
requires:
  - phase: 06-hal-signing-load-verification
    provides: signing scripts
  - phase: 08-app-virtual-device-integration
    provides: menu bar product shell
provides:
  - embed-daemon-in-app.sh
  - build-release-dmg.sh / build-release-pkg.sh
  - FirstRunPreflightView
  - docs/first-run-cubase.md
requirements-completed: [POL-01]
duration: 15min
completed: 2026-06-01
---

# Phase 10 Plan 01 Summary

**Notarized-ready DMG/pkg build scripts, embedded daemon path, and first-run Cubase preflight UI.**

## Task Commits

1. **Distribution and first-run** - `61ec3cd`

## Self-Check: PASSED

## Install path

```bash
bash scripts/build-release-pkg.sh
# → build/signing/APM44Bridge-0.1.0.pkg
sudo installer -pkg build/signing/APM44Bridge-0.1.0.pkg -target /
```

Or DMG: `bash scripts/build-release-dmg.sh` → `build/signing/APM44Bridge-0.1.0.dmg`

## Human follow-up

- Sign + notarize release container on sign-off Mac before shipping pkg/DMG to users
