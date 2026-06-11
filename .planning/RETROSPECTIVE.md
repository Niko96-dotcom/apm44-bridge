# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v0.2 — Reliability and Self-Healing

**Shipped:** 2026-06-11
**Phases:** 4 | **Plans:** 11

### What Was Built

- Deterministic app state machine with StopReason, awaitable restart, and Restart UI
- Always-on Core Audio hotplug monitoring with reconnecting state and bounded retry
- HAL stale shared-memory ring detection (driver_generation + fstat identity) with exit 42 recovery
- Audit hardening: CLI idle, IOProc clamp, SPSC overrun, shm guards, seqlock metrics, stop escalation
- CI scripts, verify-hal-driver, --shm-status, and live verification checklist

### What Worked

- Phased dependency order (state machine → hotplug → shm → hardening) prevented rework
- Injectable ProcessLaunching seam enabled thorough Swift transition tests without spawning daemons
- Wave-based plan execution kept cross-cutting constraints visible in ROADMAP
- Automated verification caught regressions early; 3/4 phases passed verification cleanly

### What Was Inefficient

- Live operator verification (QA-03) deferred to end and blocked milestone audit closure
- REQUIREMENTS.md checkbox hygiene lagged behind verification evidence (IPC-01–03)
- verify-installed-sync.sh created but not committed/CI-gated before close

### Patterns Established

- Daemon exit codes as app-recoverable contracts (exit 42 = stale shm ring)
- Non-real-time control tick for shm polling (500ms), never inside IOProc
- Seqlock metrics sync between audio/control threads and metrics tick reader

### Key Lessons

1. Operator-dependent verification should be scheduled early with explicit hardware sessions, not deferred to final phase.
2. Installed-system build-ID proof requires driver reinstall — document as prerequisite before claiming IPC-04.
3. Fix app state machine before layering auto-retry; retry policy inherits transition correctness.

### Cost Observations

- Timeline: single-day execution (2026-06-11) across 4 phases
- Velocity: ~11 plans, steady ~20 min/plan for phases 5–7

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v0.1.0 | 1-4 | Initial HAL + daemon + menu bar product |
| v0.1.1 | — | Public release cleanup, dropout fixes |
| v0.2 | 5-8 | Lifecycle reliability layer on shipped core |

### Cumulative Quality

| Milestone | Automated Tests | Live Verification |
|-----------|-----------------|-------------------|
| v0.1.1 | Cubase soak sign-off | 30+ min HAL soak |
| v0.2 | Swift transitions + Catch2 hardening | Pending operator checklist |

### Top Lessons (Verified Across Milestones)

1. The audio/DSP core was sound; lifecycle and recovery were the real failure modes.
2. CI green is necessary but not sufficient — installed driver/helper/ring sync needs explicit gates.
