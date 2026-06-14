---
phase: 41
status: passed
requirements: [QA-01, QA-02, QA-03, QA-04]
---

# Phase 41 Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Named source-audit tests for `BridgeInputOverrun`, `BridgeEngine`, `ShmIoHandler`, and mono-lane serialization exist and pass | passed | `test_hardening_audit`, `test_planar_ring_buffer`, `test_shm_io_handler`; full CTest 19/19 passed |
| `scripts/ci.sh` passes after blocker fixes | passed | `ci: OK`; native CMake/Catch2, Swift app tests, daemon embedding, installed-sync dry-run |
| Installed app/helper/driver synchronization remains verified where local machine allows it | passed with operator-owned caveat | `scripts/verify-installed-sync.sh --dry-run` reported repo/helper match; live `scripts/verify-hal-driver.sh` failed because installed HAL executable and live shm producer build are stale |
| Final release validation records Cubase 15 and USB-C AirPods Max smoke/soak evidence or marks it operator-owned | passed with operator-owned caveat | Live Cubase/AirPods validation requires admin HAL reinstall/reload and target hardware; remediation command recorded in `41-01-SUMMARY.md` |
| Requirements traceability reconciled before closeout | passed | Phase 41 summary marks QA-01..QA-04 complete with explicit caveats |

## Commands and Outcomes

- `git diff --check` -> pass
- `cmake --build build` -> pass
- `ctest --test-dir build --output-on-failure` -> 19/19 passed
- `bash scripts/ci.sh` -> `ci: OK`
- `scripts/verify-installed-sync.sh --dry-run` -> repo and embedded helper match (`0.1.1+0d3fa3104d04-dirty`)
- `scripts/verify-hal-driver.sh` -> failed: installed HAL executable differs from build; HAL smoke saw stale producer build ID `0.1.1+a4394760d996` vs helper `0.1.1+0d3fa3104d04-dirty`
- `build/BridgeDaemon/apm44-bridge --shm-status` -> failed with same stale ring build mismatch

## Operator-Owned Validation

Refresh the installed HAL driver with admin privileges, reload Core Audio, then rerun live validation:

```bash
APM44_DRIVER_PATH="$PWD/build/Driver/APM44Bridge.driver" bash scripts/install-driver.sh
bash scripts/verify-hal-driver.sh
```

Complete `docs/cubase-soak.md` on the target Cubase 15 + USB-C AirPods Max setup.
