# Phase 8 Verification Status

**Phase:** 08-hardening-and-live-verification  
**Last updated:** 2026-06-11  
**Overall:** `human_needed`

## Automated verification

| Requirement | Status | Evidence |
|-------------|--------|----------|
| QA-02 C++ hardening tests | **passed** | `test_hardening_audit`, `test_shm_stale_recovery`, `test_planar_ring_buffer` via `scripts/ci.sh` |
| QA-02 Swift latency tests | **passed** | `LatencyPresetTests` including HAL-effective fill |
| QA-03 CI | **passed** | `scripts/ci.sh` → `ci: OK` |
| QA-03 verify-installed-sync | **passed** | `verify-installed-sync.sh --dry-run` after embed; repo == helper |
| QA-03 shm-status | **passed** | `apm44-bridge --shm-status` while ring active |
| QA-03 verify-hal-driver | **partial** | Script ran; **FAIL** installed HAL SHA mismatch; **FAIL** driver vs helper build ID until `install-driver.sh` |

## Human verification required

| Requirement | Status | Blocker |
|-------------|--------|---------|
| QA-03 hotplug smoke | **human_needed** | USB-C AirPods + running bridge |
| QA-03 Cubase HAL smoke | **human_needed** | Cubase 15 + HAL route |
| QA-03 Cubase soak (15+ min) | **human_needed** | Operator presence |

See [08-LIVE-VERIFICATION.md](./08-LIVE-VERIFICATION.md) for the operator checklist and evidence table.

## Checkpoint

Live hardware verification (plan 08-03 task 3) is **not approved**. Awaiting operator `approved` signal with evidence notes.
