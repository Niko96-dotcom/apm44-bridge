---
phase: 27-release-artifact-alignment
plan: 02
subsystem: local-ci
tags: [ci, app-bundle, installed-sync, release]
provides:
  - Concrete CI app bundle path
  - Fail-closed embedded helper check before installed-sync dry-run
key-files:
  created:
    - .planning/phases/27-release-artifact-alignment/27-02-SUMMARY.md
  modified:
    - scripts/ci.sh
    - tests/test_release_scripts.sh
requirements-completed: [CI-01, CI-02, CI-03]
completed: 2026-06-13
---

# Phase 27 Plan 02 Summary: CI App Bundle Proof

## Accomplishments

- Updated `scripts/ci.sh` to use a concrete `APP_PATH` of `build/Release/APM44 Bridge.app`.
- Built Swift app verification into that output directory via `APM44_APP_OUTPUT_DIR`.
- Passed the same `APM44_APP_PATH` into daemon embedding and installed-sync verification.
- Added explicit failure checks for a missing app bundle and missing embedded daemon helper.
- Added `run_ci_03_local_ci_app_bundle_proof_check` to preserve the app path, embed, installed-sync, and helper guard behavior.

## Verification

```bash
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Result: passed. Full CI embedded `/Users/niko/apm44-bridge/build/BridgeDaemon/apm44-bridge` into `/Users/niko/apm44-bridge/build/Release/APM44 Bridge.app/Contents/MacOS/apm44-bridge`, then installed-sync dry-run verified matching repo/helper build IDs.
