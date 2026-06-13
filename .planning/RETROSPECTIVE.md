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

## Milestone: v0.4 — Public Release Blocker Closure

**Shipped:** 2026-06-12
**Phases:** 4 | **Plans:** 8

### What Was Built

- Race-free metrics publication plus safe metrics JSON truncation behavior.
- Core Audio callback edge-case coverage and clearer drop-new-input naming.
- Fail-closed notarization/release scripts with credential-free regression tests.
- Public docs for local IPC risk, DMG-first install posture, and workflow trust.
- A recorded DMG-primary release validation path with notarization, stapling,
  Gatekeeper assessment, checksum, and caveats.

### What Worked

- Closing runtime correctness before release automation kept release proof honest.
- Mocked notary tests made Apple-service failures testable without credentials.
- Treating `spctl --context context:primary-signature` as the DMG gate avoided a
  false negative from the generic assessment context.

### What Was Inefficient

- The milestone-complete SDK archive captured the roadmap before final status
  wording, so the live closeout needed a manual metadata cleanup pass.
- External publication and live hardware/DAW proof still require operator time
  after local release validation is green.

### Key Lessons

1. Public release closure needs artifact-level proof, not only CI and signed app
   bundle checks.
2. Release docs should record the exact Gatekeeper command, including context,
   because default `spctl` behavior can be misleading for DMGs.
3. DMG-first is the right public posture until signed PKG distribution is fully
   automated and verified.

---

## Milestone: v0.5 — Release Readiness Hardening

**Shipped:** 2026-06-13
**Phases:** 6 | **Plans:** 8

### What Was Built

- Data-race-free, ThreadSanitizer-clean metrics publication via atomic-field
  seqlock, plus truncation-safe metrics JSON serialization.
- Safe Core Audio failure paths: virtual-device output-start cleanup guards and
  non-interleaved input buffer clamping.
- Fail-closed release automation for notarization, unnotarized overrides, and
  app-build verification, with credential-free regression tests.
- Public local IPC threat model, accurate realtime drop-new-input naming, and
  absence guard for misleading/dead silence helpers.
- DMG inner-stapling order, DMG-primary/signed-PKG posture docs, and
  release-facing GitHub Actions trust posture regression-gated.
- Clean release validation sequence producing a signed, notarized,
  Gatekeeper-accepted DMG.

### What Worked

- Treating v0.5 as a verification-and-regression pass over v0.4 work avoided
  unnecessary reimplementation; most requirements were already correctly
  implemented and only needed requirement tags and evidence.
- Credential-free regression tests for release scripts and workflow YAML kept
  CI trust decisions enforceable without Apple credentials.
- Running the full release validation sequence after `rm -rf build` proved the
  public artifact path end-to-end, not just the incremental developer build.

### What Was Inefficient

- The milestone scope overlapped heavily with v0.4; the primary effort was
  cross-referencing existing implementation rather than building new behavior.
- No Nyquist `*-VALIDATION.md` artifacts were produced for phases 17-22, so the
  milestone relies on VERIFICATION.md and live release validation for evidence.
- Operator-dependent publication and live hardware soak remain manual steps
  after the automated gates are green.

### Patterns Established

- Requirement tags on Catch2 tests (`[CORE-01]`, `[SEC-02]`, etc.) make
  traceability from REQUIREMENTS.md to executable evidence explicit.
- Source-level guard tests (e.g., `WriteSilence` absence) prevent regression of
  removed or forbidden patterns without runtime coverage.
- Public docs keep security posture honest: local IPC is described as a
  local-machine boundary, not a privilege or authentication boundary.

### Key Lessons

1. A "second pass" milestone is valuable when the original work is correct but
   its evidence and traceability need to be release-grade.
2. Release automation trust should be enforceable by credential-free tests,
   especially when live notarization requires Apple credentials.
3. DMG-primary is the right public posture until signed PKG distribution is
   fully automated and validated.

### Cost Observations

- Timeline: single-day execution (2026-06-13) across 6 phases
- Velocity: 8 plans, ~15-30 min/plan for verification-focused work
- No new dependencies or major source rewrites

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v0.1.0 | 1-4 | Initial HAL + daemon + menu bar product |
| v0.1.1 | — | Public release cleanup, dropout fixes |
| v0.2 | 5-8 | Lifecycle reliability layer on shipped core |
| v0.4 | 13-16 | Runtime correctness and public release validation closure |
| v0.5 | 17-22 | Release-readiness verification, regression gating, and artifact hardening |

### Cumulative Quality

| Milestone | Automated Tests | Live Verification |
|-----------|-----------------|-------------------|
| v0.1.1 | Cubase soak sign-off | 30+ min HAL soak |
| v0.2 | Swift transitions + Catch2 hardening | Pending operator checklist |
| v0.4 | CI + release-script regressions + signed DMG validation | Operator publication/live soak caveats recorded |
| v0.5 | CI + TSAN metrics + release-script regressions + signed DMG Gatekeeper acceptance | DMG artifact ready for operator publication; live soak still operator-dependent |

### Top Lessons (Verified Across Milestones)

1. The audio/DSP core was sound; lifecycle and recovery were the real failure modes.
2. CI green is necessary but not sufficient — installed driver/helper/ring sync needs explicit gates.
3. Release-grade closure requires artifact-level proof (signed/notarized/stapled/Gatekeeper-accepted), not only passing repo tests.
