---
phase: 12
title: Verification Closure
status: complete
verified_at: 2026-06-12
---

# Phase 12 Verification — Verification Closure

## Goal recap

v0.3 closes with **automated hardening evidence and live
installed-system proof, or with precise hardware blockers
recorded**.

## Per-requirement verification

### QA-01 — `scripts/ci.sh` includes `verify-installed-sync.sh --dry-run`

- **Source change**: `scripts/ci.sh` now invokes
  `bash scripts/verify-installed-sync.sh --dry-run` after the
  Swift unit tests and before the final `ci: OK`.
- **Verified**: the new step is present in `scripts/ci.sh`
  and `bash scripts/ci.sh` reports
  `== Installed-sync dry-run ==` with the `OK: repo and
  embedded helper match` line.

### QA-02 — Final automated verification covers all four gates

- **Verified**: the full `bash scripts/ci.sh` run includes
  secret scan, CMake/Catch2 (20/20), Swift build, Swift tests
  (42/42), and the new installed-sync dry-run. The complete
  step-by-step table is in `12-AUTOMATED-VERIFICATION.md`.

### QA-03 — Live verification of build-ID agreement

- **Hardware-independent portion captured**: repo daemon and
  embedded helper both report
  `0.1.1+4fd2f6d43cf7-dirty`. Sync matches.
- **Live shm ring**: the ring exists (the HAL driver is
  loaded into coreaudiod). The `driver_build_id` of
  `0.1.1+a4394760d996` is the previous build's, which is the
  expected state for a freshly-built daemon on a machine
  where the installed HAL driver has not been re-installed.
  The v0.2 stale-detection contract is observing the drift
  exactly as designed.
- **Hardware portion BLOCKED**: the live shm
  `driver_build_id` cannot be made to match the current
  build without re-installing the HAL driver and reloading
  coreaudiod, both of which are operator-only.

### QA-04 — Operator evidence checklist

- **Captured**: 6 of 10 items (verify-installed-sync dry-run,
  repo/helper `--version`, `--shm-status`,
  `verify-hal-driver.sh`).
- **Blocked**: 4 items (fresh-driver install + coreaudiod
  reload, `--shm-status` with the bridge running, USB-C
  AirPods hotplug smoke, Cubase HAL smoke/soak). The full
  checklist with `[x]` / `[ ] BLOCKED:` tags is in
  `12-LIVE-VERIFICATION.md`.

### QA-05 — Hardware-only caveat recorded

- **Captured**: `12-LIVE-VERIFICATION.md` ends with a
  "QA-05 Hardware-only caveat" section that states the
  dev-environment CI proof is sufficient for the v0.3
  milestone archive, lists the 4 hardware-blocked items with
  the exact unblock step for each, and cross-references the
  v0.2 baseline.

## Build / test results

| Suite | Result |
| --- | --- |
| `bash scripts/ci.sh` (full gate) | `ci: OK` (exit 0) |
| ctest | 20/20 passed |
| xcodebuild test | 42/42 passed |
| `verify-installed-sync.sh --dry-run` | OK |
| `apm44-bridge --shm-status` | shm live, expected drift observed |
| `verify-hal-driver.sh` | 2 expected FAILs (previous-build driver + previous-build ring) |

## Deviations

None at the source level. The first CI run caught a real
build-ID drift between the repo daemon and the embedded
helper — re-embedding via `scripts/embed-daemon-in-app.sh`
fixed it. This is a positive outcome of the new gate, not a
defect.

## Phase 12 result

**Complete.** All five QA-01..QA-05 requirements met. The
dev-environment CI proof is sufficient for the v0.3 milestone
archive. The four hardware-blocked items are recorded with
exact unblock steps for the next release pass on a
real-hardware machine.
