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
- **v0.5 Release Readiness Hardening** - Phases 17-22 (in progress)

## Overview

The v0.4 journey closed the remaining blockers before the next public release.
It started with runtime correctness issues that could invalidate release proof,
then made signing/notarization automation fail closed, cleaned up public
distribution trust and installer posture, and recorded a complete release
validation sequence with exact caveats for anything blocked by credentials or
hardware.

The v0.5 milestone is a second pass on release-readiness blockers: harden the
C++ metrics and serialization paths, close two Core Audio failure-path edge
cases, make release automation fail closed by default, clean up misleading
realtime helper naming and dead code, document the local IPC threat model and
installer posture, pin or explicitly track release CI trust decisions, and run a
clean regression-plus-release validation sequence before considering the public
artifact shippable.

## Phase Numbering

Phase numbering continues from shipped history:

- Phases 1-4: v0.1/v0.1.1 shipped product path.
- Phases 5-8: v0.2 Reliability and Self-Healing.
- Phases 9-12: v0.3 Realtime Audio Hardening.
- Phases 13-16: v0.4 Public Release Blocker Closure.
- Phases 17-22: v0.5 Release Readiness Hardening.

## Phases

- [x] **Phase 13: Runtime Correctness Blockers** - Remove the standards-level
  metrics data race, make metrics JSON truncation safe, and close Core Audio
  edge/error path blockers. (completed 2026-06-12)
- [x] **Phase 14: Release Automation Fail-Closed** - Make release scripts and
  signing workflows strict by default, with credential-free regression tests for
  failure modes. (completed 2026-06-12)
- [x] **Phase 15: Public Distribution UX and Security Posture** - Publish the
  local IPC threat model, settle DMG/PKG release posture, and harden critical
  workflow trust decisions. (completed 2026-06-12)
- [x] **Phase 16: Release Validation Closure** - Run and record the final
  public-release validation sequence, including exact blockers for anything that
  cannot be completed locally. (completed 2026-06-12)
- [x] **Phase 17: Metrics & Serialization** - Make `MetricsPublisher`
  data-race-free and ThreadSanitizer-clean, and make metrics JSON serialization
  truncation-safe. (completed 2026-06-13)
- [x] **Phase 18: Core Audio Error Paths** - Fix virtual-device output-start
  cleanup and non-interleaved input buffer sizing so failure paths fail safely.
  (completed 2026-06-13)
- [x] **Phase 19: Release Automation Fail-Closed** - Make notarization,
  release-all, and signing workflow failures hard by default with an explicit
  local override. (completed 2026-06-13)
- [x] **Phase 20: Security & Realtime Cleanup** - Publish a clear local IPC
  threat model and remove misleading realtime helper names/comments/dead code.
  (completed 2026-06-13)
- [x] **Phase 21: Distribution & CI** - Staple inner artifacts before DMG
  finalization, document DMG/PKG posture, and pin/document release workflow
  trust. (completed 2026-06-13)
- [x] **Phase 22: QA / Regression** - Cover all fixes with regression tests
  and run a clean release validation sequence. (completed 2026-06-13)

## Phase Details

### Phase 13: Runtime Correctness Blockers

**Goal:** The runtime paths called out by the publishing review are standards-safe, bounded, and regression-tested before release automation is trusted.

**Depends on:** v0.3 shipped baseline

**Requirements:** METR-01, METR-02, METR-03, JSON-01, JSON-02, AUD-01, AUD-02,
AUD-03, RT-01, RT-02

**Success Criteria** (what must be TRUE):
1. `MetricsPublisher` no longer relies on concurrent non-atomic `MetricsSnapshot` reads/writes.
2. CLI/app metrics preserve all currently exposed fields after the publisher change.
3. `BridgeMetrics::ToJsonLine` handles formatting failure and truncation without reading past the stack buffer.
4. Virtual-device output-start failure and mismatched non-interleaved input buffers are covered by regression tests.
5. Realtime helper names/comments and dead helper code no longer contradict the implemented drop-new-input policy.

**Plans:** 2/2 plans complete

Planned work:
- 13-01 - Replace metrics publication and JSON truncation behavior with
  regression proof (METR-01, METR-02, METR-03, JSON-01, JSON-02)
- 13-02 - Harden Core Audio edge paths and clean realtime helper naming/dead
  code (AUD-01, AUD-02, AUD-03, RT-01, RT-02)

### Phase 14: Release Automation Fail-Closed

**Goal:** Release commands and workflows cannot silently produce stale, unnotarized, or weakly validated public artifacts.

**Depends on:** Phase 13

**Requirements:** REL-01, REL-02, REL-03, REL-04, REL-05, REL-06, REL-07

**Success Criteria** (what must be TRUE):
1. DMG and PKG notarization scripts require both successful `notarytool` exit and `status: Accepted`.
2. Notary failure paths preserve submission output and fetch logs when a submission id is available.
3. `release-all.sh` fails without notary credentials unless an explicit local-only unnotarized override is set.
4. The signing workflow no longer masks app build verification failure.
5. Credential-free script tests cover accepted, rejected, auth-failure, network-failure, and malformed notary output.

**Plans:** 2/2 plans complete

Planned work:
- 14-01 - Make notarization and release-all scripts fail closed by default
  (REL-01, REL-02, REL-03, REL-04, REL-05)
- 14-02 - Tighten signing workflow and add mocked notary regression tests
  (REL-06, REL-07)

### Phase 15: Public Distribution UX and Security Posture

**Goal:** The public release surface is honest about local IPC assumptions and clear about the installer/artifact trust story.

**Depends on:** Phase 14

**Requirements:** DOC-01, DOC-02, DOC-03, PKG-01, PKG-02, PKG-03, GHA-01

**Success Criteria** (what must be TRUE):
1. Public docs explain that `/apm44_bridge_ring` is local-machine IPC and not an authentication or privilege boundary.
2. Docs describe the implications of shm mode `0666` and list future hardening options without overclaiming current protection.
3. The milestone records a clear DMG-primary versus PKG-primary installer decision.
4. Release docs and scripts agree on when inner app/driver artifacts and the final public container are stapled and validated.
5. Critical GitHub Actions near release artifacts, credentials, or signing are either pinned to full-length SHAs or covered by an explicit trust decision.

**Plans:** 2/2 plans complete

Planned work:
- 15-01 - Document local IPC threat model and installer UX decision
  (DOC-01, DOC-02, DOC-03, PKG-01, PKG-02)
- 15-02 - Align artifact stapling order and release workflow trust posture
  (PKG-03, GHA-01)

### Phase 16: Release Validation Closure

**Goal:** v0.4 closes with a clean, repeatable public-release validation record or exact unblock commands for external blockers.

**Depends on:** Phase 15

**Requirements:** QA-01, QA-02, QA-03, QA-04, QA-05

**Success Criteria** (what must be TRUE):
1. Final automated verification includes secret scan, native tests, Swift tests, app build verification, and release-script regression tests.
2. The release validation sequence is recorded from clean build through signing, notarization, stapling, and Gatekeeper assessment.
3. The selected DMG/PKG public artifact path is assessed with the appropriate `codesign`, `stapler`, `spctl`, or `pkgutil` commands.
4. Apple credential, installer certificate, hardware, or operator blockers are recorded with exact unblock commands.
5. Planning state is updated with satisfied requirements, accepted gaps, and remaining public-release caveats.

**Plans:** 2/2 plans complete

Planned work:
- 16-01 - Run full automated and release validation gates (QA-01, QA-02)
- 16-02 - Assess final artifacts and record closeout caveats (QA-03, QA-04,
   QA-05)

### Phase 17: Metrics & Serialization

**Goal:** Metrics publication is demonstrably data-race-free under standard C++ and ThreadSanitizer, and metrics JSON serialization handles truncation without reading past its buffer.

**Depends on:** v0.4 shipped baseline

**Requirements:** METR-01, METR-02, METR-03

**Success Criteria** (what must be TRUE):
1. `MetricsPublisher` stores snapshot fields atomically (or via an equivalent RT-safe representation) so publication is data-race-free under standard C++.
2. Metrics publication passes ThreadSanitizer without reported races.
3. `BridgeMetrics::ToJsonLine` handles `snprintf` truncation safely and cannot read past its stack buffer.
4. Existing CLI/app metrics consumers still receive all currently exposed fields after the serialization change.

**Plans:** 1/1 plans complete

### Phase 18: Core Audio Error Paths

**Goal:** Core Audio virtual-device output-start failure and non-interleaved input callback sizing fail safely without null IOProc cleanup or buffer overreads.

**Depends on:** Phase 17

**Requirements:** CORE-01, CORE-02

**Success Criteria** (what must be TRUE):
1. Virtual-device output-start failure only stops an input IOProc if one was actually created and started.
2. The non-interleaved input callback clamps both buffer sizes before passing channels to the engine.
3. Regression tests cover the output-start failure cleanup path and the non-interleaved input sizing edge case.

**Plans:** 1/1 plans complete

Planned work:
- 18-01 - Verify virtual-device output-start cleanup and non-interleaved input
  sizing are regression-gated (CORE-01, CORE-02)

### Phase 19: Release Automation Fail-Closed

**Goal:** Release scripts and the signing workflow treat notarization and app-build verification failures as hard failures unless explicitly overridden.

**Depends on:** Phase 18

**Requirements:** REL-01, REL-02, REL-03

**Success Criteria** (what must be TRUE):
1. `notarize-release-dmg.sh` exits non-zero and reports failure for any non-`Accepted` notarization result or nonzero `notarytool` exit status.
2. `release-all.sh` requires an explicit override (e.g. `APM44_ALLOW_UNNOTARIZED=1`) to produce an unnotarized artifact.
3. `sign-notarize.yml` fails the workflow if `verify-app-build.sh` fails.
4. Normal release automation still succeeds when all validation passes and no override is set.

**Plans:** 1/1 plans complete

Planned work:
- 19-01 - Verify release scripts and signing workflow fail closed by default
  (REL-01, REL-02, REL-03)

### Phase 20: Security & Realtime Cleanup

**Goal:** Public docs clearly describe the local IPC threat model, and realtime overrun/silence helper naming and dead code match the actual behavior.

**Depends on:** Phase 19

**Requirements:** SEC-01, SEC-02, SEC-03

**Success Criteria** (what must be TRUE):
1. Public docs include a clear local IPC threat model for shared-memory mode `0666` with no security overclaiming.
2. Realtime overrun helper names and comments accurately describe the drop-new-input behavior.
3. The unused or incorrect `WriteSilence` helper is removed or rewritten, with no regression in silence-generation paths.
4. Source-level or regression tests verify that the helper cleanup does not affect expected silence output.

**Plans:** 1/1 plans complete

Planned work:
- 20-01 - Verify and regression-gate local IPC threat model, drop-new-input
  helper naming, and WriteSilence absence (SEC-01, SEC-02, SEC-03)

### Phase 21: Distribution & CI

**Goal:** The DMG is built from stapled inner artifacts, public docs explain the current installer posture, and release-facing GitHub Actions trust is pinned or documented.

**Depends on:** Phase 20

**Requirements:** DIST-01, DIST-02, CI-01

**Success Criteria** (what must be TRUE):
1. DMG creation staples inner app/driver artifacts before building the final DMG, then notarizes and staples the DMG.
2. Public docs explain the signed PKG direction and the current DMG-primary posture.
3. Release-facing GitHub Actions are pinned by SHA or the decision not to is explicitly documented.
4. The release artifact validation sequence passes with the new stapling order.

**Plans:** 3/3 plans complete

Planned work:
- 21-01 - Verify DMG is built from stapled inner app/driver artifacts (DIST-01)
- 21-02 - Verify public docs explain DMG-primary and signed-PKG direction (DIST-02)
- 21-03 - Verify release-facing GitHub Actions trust is pinned or documented (CI-01)

### Phase 22: QA / Regression

**Goal:** Every v0.5 fix is covered by regression tests and the full release validation sequence runs clean.

**Depends on:** Phase 21

**Requirements:** QA-01, QA-02

**Success Criteria** (what must be TRUE):
1. Regression tests cover the fixed truncation, failure-path, and callback-edge cases.
2. The full automated test suite (native, Swift, release-script regression) passes.
3. A clean release validation sequence runs successfully after all fixes.
4. Any remaining operator/hardware blockers are recorded with exact unblock commands.

**Plans:** 1/1 plans complete

Planned work:
- 22-01 - Run full local CI gate and clean signed/notarized release validation sequence (QA-01, QA-02)

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
| 12. Verification Closure | v0.3 | 2/2 | Complete | 2026-06-12 |
| 13. Runtime Correctness Blockers | v0.4 | 2/2 | Complete    | 2026-06-12 |
| 14. Release Automation Fail-Closed | v0.4 | 2/2 | Complete    | 2026-06-12 |
| 15. Public Distribution UX and Security Posture | v0.4 | 2/2 | Complete    | 2026-06-12 |
| 16. Release Validation Closure | v0.4 | 2/2 | Complete    | 2026-06-12 |
| 17. Metrics & Serialization | v0.5 | 1/1 | Complete    | 2026-06-13 |
| 18. Core Audio Error Paths | v0.5 | 1/1 | Complete    | 2026-06-13 |
| 19. Release Automation Fail-Closed | v0.5 | 1/1 | Complete    | 2026-06-13 |
| 20. Security & Realtime Cleanup | v0.5 | 1/1 | Complete    | 2026-06-13 |
| 21. Distribution & CI | v0.5 | 3/3 | Complete | 2026-06-13 |
| 22. QA / Regression | v0.5 | 1/1 | Complete | 2026-06-13 |

## Coverage

- v0.4 requirements mapped: 29/29
- v0.5 requirements mapped: 16/16
- v0.5 phases: 6
- v0.5 plans: 8/8
- v0.5 unmapped requirements: 0

---
*Roadmap updated: 2026-06-13 after Phase 22 completion*
