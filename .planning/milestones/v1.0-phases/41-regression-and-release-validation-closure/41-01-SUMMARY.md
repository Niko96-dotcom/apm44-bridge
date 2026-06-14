---
phase: 41
plan: 01
status: complete
requirements-completed: [QA-01, QA-02, QA-03, QA-04]
key_files:
  modified:
    - .planning/REQUIREMENTS.md
    - .planning/phases/41-regression-and-release-validation-closure/41-VERIFICATION.md
---

# 41-01 Summary: Run final v1.0 regression and release validation

## Completed

- Confirmed source-audit and behavior tests cover the Phase 38-40 race-blocker contracts.
- Ran the full local CI gate successfully: `ci: OK`.
- Captured installed app/helper sync dry-run success.
- Captured live HAL driver validation truthfully: the installed system driver/ring is older than the repo build and requires an admin reinstall/reload before live Cubase/AirPods validation.
- Recorded Cubase 15 and USB-C AirPods Max live smoke/soak as operator-owned validation.

## Verification

- `bash scripts/ci.sh` -> `ci: OK`
- `scripts/verify-installed-sync.sh --dry-run` -> repo and embedded helper match
- `scripts/verify-hal-driver.sh` -> failed because installed HAL executable and live ring build ID differ from current build
- `build/BridgeDaemon/apm44-bridge --shm-status` -> failed with stale producer build ID in live shm ring

## Operator-Owned Follow-Up

To refresh the installed HAL driver and live ring:

```bash
APM44_DRIVER_PATH="$PWD/build/Driver/APM44Bridge.driver" bash scripts/install-driver.sh
```

Then rerun:

```bash
bash scripts/verify-hal-driver.sh
bash docs/cubase-soak.md checklist manually with Cubase 15 and USB-C AirPods Max
```
