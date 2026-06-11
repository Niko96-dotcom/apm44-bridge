# Roadmap: APM44 Bridge

## Milestones

- Complete **v0.1.0 Initial Distribution** - Phases 1-4 (shipped 2026-06-01)
- Complete **v0.1.1 Public Release** - HAL dropout recovery, metrics clarity,
  notarized DMG (shipped 2026-06-03)
- Complete **v0.2 Reliability and Self-Healing** - Phases 5-8 (shipped
  2026-06-11) - [archive](milestones/v0.2-ROADMAP.md)
- In progress **v0.3 Realtime Audio Hardening** - Phases 9-12

## Overview

The v0.3 journey hardens the shipped Cubase -> APM44 HAL -> daemon -> USB-C
AirPods path before new packaging or DAW expansion. It starts at the realtime
callback boundary, then fixes process/metrics races, then validates shared
memory defensively, and closes with automated and live installed-system proof.

## Phase Numbering

Phase numbering continues from shipped history:

- Phases 1-4: v0.1/v0.1.1 shipped product path.
- Phases 5-8: v0.2 Reliability and Self-Healing.
- Phases 9-12: v0.3 Realtime Audio Hardening.

## Phases

- [x] **Phase 9: Realtime Callback Ownership** - Preserve SPSC ring ownership
  and make oversized output callbacks deterministic.
- [x] **Phase 10: Process and Metrics Race Hardening** - Make stop escalation
  timeout-safe and publish metrics through a C++ race-free path.
- [x] **Phase 11: Shared-Memory Validation Hardening** - Reject truncated or
  corrupt shm mappings before trusting header capacity or build IDs.
- [ ] **Phase 12: Verification Closure** - Gate non-hardware sync checks and
  capture live installed-system evidence or exact hardware blockers.

## Phase Details

### Phase 9: Realtime Callback Ownership

**Goal:** The realtime audio callbacks obey their ownership contracts and never
leave Core Audio output frames stale.

**Depends on:** v0.2 shipped baseline

**Requirements:** RT-01, RT-02, RT-03, RT-04, RT-05

**Success Criteria** (what must be TRUE):
1. Input overrun handling never calls `PlanarRingBuffer::pop()` or otherwise
   mutates consumer-owned state from the producer path.
2. The chosen overrun behavior is documented in code/tests and either drops
   incoming frames or performs oldest-frame trimming only from the output side.
3. Interleaved and non-interleaved output callbacks larger than the scratch
   capacity render or explicitly silence every actual frame.
4. Native regression tests cover the selected overrun policy and oversized
   callback behavior without touching `/apm44_bridge_ring`.

**Plans:** 2/2 plans complete

Planned work:
- 09-01 - Replace producer-side drop-oldest policy and update SPSC tests
  (RT-01, RT-02, RT-05)
- 09-02 - Make oversized output callbacks render/silence the whole buffer
  (RT-03, RT-04, RT-05)

### Phase 10: Process and Metrics Race Hardening

**Goal:** Process-stop/restart coordination and metrics publication are
deterministic under timeout and cross-thread access.

**Depends on:** Phase 9

**Requirements:** PROC-01, PROC-02, PROC-03, PROC-04, METR-01, METR-02, METR-03

**Success Criteria** (what must be TRUE):
1. A daemon that ignores graceful termination reaches the SIGKILL escalation path
   and returns a final result instead of hanging.
2. Concurrent stop/restart waiters complete independently without one waiter
   overwriting another.
3. Metrics read by CLI/control/UI paths are published with no C++ data race.
4. Swift and native tests cover termination timeout/escalation, concurrent
   waiters, and the metrics publication contract.

**Plans:** 2/2 plans complete

Planned work:
- 10-01 - Replace single termination continuation with explicit waiter
  bookkeeping and escalation tests (PROC-01, PROC-02, PROC-03, PROC-04)
- 10-02 - Replace metrics seqlock/plain payload with race-free publication and
  regression coverage (METR-01, METR-02, METR-03)

### Phase 11: Shared-Memory Validation Hardening

**Goal:** The daemon rejects malformed HAL shared-memory objects safely before
any ring operation trusts their declared layout.

**Depends on:** Phase 10

**Requirements:** SHM-01, SHM-02, SHM-03, SHM-04, SHM-05

**Success Criteria** (what must be TRUE):
1. `MmapShmRing::open()` rejects objects smaller than `ShmRingHeader` before
   reading header fields.
2. `MmapShmRing::open()` rejects valid-looking headers whose mapped size is
   smaller than `ShmTotalSize(capacity_frames)`.
3. Live generation reads check object size before mapping or reading a header.
4. Header mismatch diagnostics use bounded build-ID rendering.
5. Catch2 tests cover truncated, header-only, huge-capacity, and unterminated
   build-ID cases with isolated test shm names.

**Plans:** 2/2 plans complete

Planned work:
- 11-01 - Add shm size validation before header/capacity trust (SHM-01, SHM-02,
  SHM-03)
- 11-02 - Add bounded corrupt-header diagnostics and isolated shm regression
  tests (SHM-04, SHM-05)

### Phase 12: Verification Closure

**Goal:** v0.3 closes with automated hardening evidence and live installed-system
proof, or with precise hardware blockers recorded.

**Depends on:** Phase 11

**Requirements:** QA-01, QA-02, QA-03, QA-04, QA-05

**Success Criteria** (what must be TRUE):
1. `scripts/ci.sh` includes a non-hardware dry-run check for
   `scripts/verify-installed-sync.sh`.
2. Final automated verification includes secret scan, CMake/Catch2 tests, Swift
   app build/tests, and installed-sync dry-run.
3. Live verification records repo daemon, embedded app helper, installed HAL
   driver, and live shm ring build-ID agreement, or the exact blocker.
4. Operator evidence covers `verify-hal-driver.sh`, `--shm-status`, USB-C
   AirPods hotplug smoke, and Cubase HAL smoke/soak where hardware is available.
5. Milestone close records any remaining hardware-only caveat instead of
   treating CI-only proof as complete.

**Plans:** 0/2 plans complete

Planned work:
- 12-01 - Add installed-sync dry-run to CI and run full automated gates
  (QA-01, QA-02)
- 12-02 - Capture live installed-system and operator proof, or precise blocker
  record (QA-03, QA-04, QA-05)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-4. Shipped product path | v0.1/v0.1.1 | - | Complete | 2026-06-03 |
| 5. App State Machine and Deterministic Restart | v0.2 | 3/3 | Complete | 2026-06-11 |
| 6. Always-On Device Recovery | v0.2 | 2/2 | Complete | 2026-06-11 |
| 7. HAL IPC Self-Healing | v0.2 | 3/3 | Complete | 2026-06-11 |
| 8. Hardening and Live Verification | v0.2 | 3/3 | Complete | 2026-06-11 |
| 9. Realtime Callback Ownership | v0.3 | 2/2 | Complete | 2026-06-12 |
| 10. Process and Metrics Race Hardening | v0.3 | 2/2 | Complete | 2026-06-12 |
| 11. Shared-Memory Validation Hardening | v0.3 | 2/2 | Complete | 2026-06-12 |
| 12. Verification Closure | v0.3 | 0/2 | Ready to plan | - |

## Coverage

- Requirements mapped: 22/22
- Phases: 4
- Plans: 8 proposed
- Unmapped requirements: 0

---
*Roadmap updated: 2026-06-12 after Phase 11 verification*
