---
phase: 08-hardening-and-live-verification
plan: 03
subsystem: verification
tags: [ci, hal, live-checklist, shm-status]
requires:
  - phase: 08-hardening-and-live-verification
    provides: hardened tree and regression tests from 08-01/08-02
provides:
  - scripts/verify-installed-sync.sh
  - 08-LIVE-VERIFICATION.md operator checklist
  - VERIFICATION.md with human_needed status
affects: [milestone-v0.2-archive]
tech-stack:
  added: [scripts/verify-installed-sync.sh]
  patterns: [build ID triangulation repo/helper/shm]
key-files:
  created: [scripts/verify-installed-sync.sh, 08-LIVE-VERIFICATION.md, VERIFICATION.md]
  modified: []
key-decisions:
  - "Live Cubase/AirPods marked human_needed; automated CI/sync documented"
requirements-completed: []
duration: 15min
completed: 2026-06-11
---

# Phase 8 Plan 03: Live Verification Summary

**CI green, installed-sync script, shm-status proof, and hardware checklist awaiting operator**

## Performance

- **Duration:** ~15 min
- **Tasks:** 2 automated (+ checkpoint pending)
- **Files created:** 3

## Automated evidence

```
scripts/ci.sh → ci: OK
ctest: 18/18 passed
Swift: 41/41 passed
verify-installed-sync.sh --dry-run → repo_build_id == helper_build_id (0.1.1+543ca08019de)
apm44-bridge --shm-status → helper_build_id=0.1.1+543ca08019de (driver_build_id stale until reinstall)
verify-hal-driver.sh → FAIL installed SHA mismatch; WARN Gatekeeper on build bundle
```

## Task Commits

1. **CI + verify-installed-sync.sh** - `f0b728f`
2. **Live checklist + VERIFICATION.md** - `497b11a`
3. **Plan summaries** - `35aaba5`

## Checkpoint status

**Task 3 (live hotplug + Cubase):** `human_needed` — see [08-LIVE-VERIFICATION.md](./08-LIVE-VERIFICATION.md)

## Deviations from Plan

None for automated scope. Driver reinstall requires sudo — documented in checklist, not executed in agent environment.

## Self-Check: PASSED

- scripts/verify-installed-sync.sh: FOUND
- 08-LIVE-VERIFICATION.md: FOUND
- VERIFICATION.md: FOUND

---
*Phase: 08-hardening-and-live-verification*
*Completed: 2026-06-11*
