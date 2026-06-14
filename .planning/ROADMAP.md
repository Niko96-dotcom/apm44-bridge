# Roadmap: APM44 Bridge

## Milestones

- Complete **v0.1.0 Initial Distribution** - Phases 1-4 (shipped 2026-06-01)
- Complete **v0.1.1 Public Release** - HAL dropout recovery, metrics clarity,
  notarized DMG (shipped 2026-06-03)
- Complete **v0.2 Reliability and Self-Healing** - Phases 5-8 (shipped
  2026-06-11) - [archive](milestones/v0.2-ROADMAP.md)
- Complete **v0.3 Realtime Audio Hardening** - Phases 9-12 (shipped
  2026-06-12) - [archive](milestones/v0.3-ROADMAP.md)
- Complete **v0.4 Public Release Blocker Closure** - Phases 13-16 (shipped
  2026-06-12) - [archive](milestones/v0.4-ROADMAP.md)
- Complete **v0.5 Release Readiness Hardening** - Phases 17-22 (shipped
  2026-06-13) - [archive](milestones/v0.5-ROADMAP.md)
- Complete **v0.6 Public Release Safety Fixes** - Phases 23-26 (shipped
  2026-06-13) - [archive](milestones/v0.6-ROADMAP.md)
- Complete **v0.7 Release Automation Final Polish** - Phases 27-29 (shipped
  2026-06-13) - [archive](milestones/v0.7-ROADMAP.md)
- Complete **v0.8 Release Candidate Closure** - Phases 30-32 (shipped
  2026-06-13) - [archive](milestones/v0.8-ROADMAP.md)
- Complete **v0.9 Public Polish Final Hardening** - Phases 33-37 (shipped
  2026-06-14) - [archive](milestones/v0.9-ROADMAP.md)
- Active **v1.0 Realtime Race Blocker Closure** - Phases 38-41

## Overview

v1.0 closes the realtime race blockers identified in the 2026-06-14 audit. The
milestone removes producer-side mutation of `DriftController`, makes the HAL
stopped-IO guard atomic, proves or contains mono-lane callback serialization,
and adds source-level regression tests so the release path does not drift back
into unsafe cross-callback mutable state.

## Phase Numbering

Phase numbering continues from shipped history:

- Phases 1-4: v0.1/v0.1.1 shipped product path.
- Phases 5-8: v0.2 Reliability and Self-Healing.
- Phases 9-12: v0.3 Realtime Audio Hardening.
- Phases 13-16: v0.4 Public Release Blocker Closure.
- Phases 17-22: v0.5 Release Readiness Hardening.
- Phases 23-26: v0.6 Public Release Safety Fixes.
- Phases 27-29: v0.7 Release Automation Final Polish.
- Phases 30-32: v0.8 Release Candidate Closure.
- Phases 33-37: v0.9 Public Polish Final Hardening.
- Phases 38-41: v1.0 Realtime Race Blocker Closure.

## Phases

- [ ] **Phase 38: Input and Output Drift Ownership** - Remove input-callback
  `DriftController` mutation and publish input overruns through an atomic
  counter.
- [ ] **Phase 39: HAL IO Running Atomic Guard** - Make `ioRunning_` atomic and
  preserve stopped-IO behavior with regression coverage.
- [ ] **Phase 40: Mono-Lane Callback Serialization Proof** - Prove/document
  libASPL callback serialization or redesign lane assembly to avoid unsafe
  shared mutable callback state.
- [ ] **Phase 41: Regression and Release Validation Closure** - Add source-audit
  guards, run full CI, and record release/soak evidence and caveats.

## Phase Details

### Phase 38: Input and Output Drift Ownership

**Goal:** Input callbacks only produce audio and count dropped input atomically;
output callbacks exclusively own drift control state.

**Depends on:** v0.9 shipped baseline

**Requirements:** DRIFT-01, DRIFT-02, DRIFT-03, DRIFT-04, DRIFT-05

**Success Criteria** (what must be TRUE):
1. `BridgeInputOverrun.h` has no `DriftController` dependency and no
   `notifyOverrun` reference.
2. `PushDroppingNewInput` returns whether the ring accepted fewer frames than
   requested.
3. `BridgeEngine::onInput` increments a dedicated `std::atomic<uint64_t>` when
   input frames are dropped.
4. Drift PI update, underrun notification, and drift metrics reads remain
   output-thread-owned.
5. Source-audit and behavior tests fail if producer-side drift mutation returns.

**Planned work:**
- 38-01 - Remove producer-side drift mutation from `BridgeInputOverrun` and
  `BridgeEngine::onInput` (DRIFT-01, DRIFT-02, DRIFT-03)
- 38-02 - Route metrics overrun reporting through the atomic input-overrun
  counter and add regression tests (DRIFT-04, DRIFT-05)

### Phase 39: HAL IO Running Atomic Guard

**Goal:** HAL start/stop/control callbacks and mixed-output callbacks share the
stopped-IO guard without a standard C++ data race.

**Depends on:** Phase 38

**Requirements:** HALIO-01, HALIO-02, HALIO-03, HALIO-04

**Success Criteria** (what must be TRUE):
1. `ShmIoHandler.h` includes `<atomic>` and declares
   `std::atomic<bool> ioRunning_{false}`.
2. `OnStartIO`, `OnStopIO`, and `OnProcessMixedOutput` use an explicit load/store
   memory-ordering contract.
3. Existing stopped-IO behavior remains unchanged: output processing returns
   without pushing frames while IO is stopped.
4. Source-audit or behavior tests fail if `ioRunning_` becomes a plain `bool`
   again.

**Planned work:**
- 39-01 - Make `ioRunning_` atomic and document/apply the callback memory-order
  contract (HALIO-01, HALIO-02)
- 39-02 - Preserve stopped-IO behavior and add regression/source guards
  (HALIO-03, HALIO-04)

### Phase 40: Mono-Lane Callback Serialization Proof

**Goal:** Mono-lane assembly no longer relies on an unstated host callback
serialization assumption.

**Depends on:** Phase 39

**Requirements:** MONO-01, MONO-02, MONO-03, MONO-04

**Success Criteria** (what must be TRUE):
1. The code cites the relevant libASPL/Core Audio serialization contract, or the
   lane assembly state is redesigned to be safe under concurrent callbacks.
2. Tests exercise the serialized left/right callback pattern expected by the
   handler.
3. Existing timestamp/logical-sample mismatch protections still drop unrelated
   lanes instead of pairing skewed stereo data.
4. A source-audit guard prevents shared mono-lane callback state from existing
   without an explicit serialization contract or safe redesign.

**Planned work:**
- 40-01 - Prove/document the mono-lane callback serialization contract or select
  the safe redesign path (MONO-01, MONO-03)
- 40-02 - Add serialized mono-lane pattern tests while preserving mismatch/drop
  coverage (MONO-02, MONO-04)

### Phase 41: Regression and Release Validation Closure

**Goal:** v1.0 closes with hard regression guards, full repo validation, and
truthful release/soak evidence.

**Depends on:** Phase 40

**Requirements:** QA-01, QA-02, QA-03, QA-04

**Success Criteria** (what must be TRUE):
1. The named source-audit tests for `BridgeInputOverrun`, `BridgeEngine`,
   `ShmIoHandler`, and mono-lane serialization exist and pass.
2. `scripts/ci.sh` passes after all blocker fixes.
3. Installed app/helper/driver synchronization remains verified through the
   repo's trusted verification entrypoints where the local machine allows it.
4. Final release validation records Cubase 15 and USB-C AirPods Max smoke/soak
   evidence or explicitly marks it operator-owned.
5. Requirements traceability is reconciled before milestone closeout.

**Planned work:**
- 41-01 - Add final source-audit guards and run full v1.0 regression/release
  validation (QA-01, QA-02, QA-03, QA-04)

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DRIFT-01 | Phase 38 | Pending |
| DRIFT-02 | Phase 38 | Pending |
| DRIFT-03 | Phase 38 | Pending |
| DRIFT-04 | Phase 38 | Pending |
| DRIFT-05 | Phase 38 | Pending |
| HALIO-01 | Phase 39 | Pending |
| HALIO-02 | Phase 39 | Pending |
| HALIO-03 | Phase 39 | Pending |
| HALIO-04 | Phase 39 | Pending |
| MONO-01 | Phase 40 | Pending |
| MONO-02 | Phase 40 | Pending |
| MONO-03 | Phase 40 | Pending |
| MONO-04 | Phase 40 | Pending |
| QA-01 | Phase 41 | Pending |
| QA-02 | Phase 41 | Pending |
| QA-03 | Phase 41 | Pending |
| QA-04 | Phase 41 | Pending |

**Coverage:** 17/17 requirements mapped.

## Verification Gates

- `scripts/ci.sh`
- Targeted native/source-audit tests for `BridgeInputOverrun`, `BridgeEngine`,
  `ShmIoHandler`, and mono-lane callback serialization
- `scripts/verify-installed-sync.sh`
- `scripts/verify-hal-driver.sh`
- `apm44-bridge --shm-status`
- Target Cubase 15 and USB-C AirPods Max smoke/soak validation when hardware is
  available

## Next Step

Start Phase 38 with `$gsd-plan-phase 38`.

---
*Last updated: 2026-06-14 after v1.0 roadmap creation*
