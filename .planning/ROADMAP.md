# Roadmap: APM44 Bridge

## Milestones

- Complete **v0.1.0 Initial Distribution** - Phases 1-4 (shipped 2026-06-01)
- Complete **v0.1.1 Public Release** - HAL dropout recovery, metrics clarity,
  notarized DMG (shipped 2026-06-03)
- Complete **v0.2 Reliability and Self-Healing** - Phases 5-8 (shipped
  2026-06-11) - [archive](milestones/v0.2-ROADMAP.md)
- Complete **v0.3 Realtime Audio Hardening** - Phases 9-12 (shipped
  2026-06-12) - [archive](milestones/v0.3-ROADMAP.md)
- Planned **v0.4 Public Release Blocker Closure** - Phases 13-16

## Overview

The v0.4 journey closes the remaining blockers before the next public release.
It starts with runtime correctness issues that could invalidate release proof,
then makes signing/notarization automation fail closed, then cleans up public
distribution trust and installer posture, and finally records a complete release
validation sequence with exact caveats for anything blocked by credentials or
hardware.

## Phase Numbering

Phase numbering continues from shipped history:

- Phases 1-4: v0.1/v0.1.1 shipped product path.
- Phases 5-8: v0.2 Reliability and Self-Healing.
- Phases 9-12: v0.3 Realtime Audio Hardening.
- Phases 13-16: v0.4 Public Release Blocker Closure.

## Phases

- [x] **Phase 13: Runtime Correctness Blockers** - Remove the standards-level (completed 2026-06-12)
  metrics data race, make metrics JSON truncation safe, and close Core Audio
  edge/error path blockers.
- [x] **Phase 14: Release Automation Fail-Closed** - Make release scripts and (completed 2026-06-12)
  signing workflows strict by default, with credential-free regression tests for
  failure modes.
- [x] **Phase 15: Public Distribution UX and Security Posture** - Publish the (completed 2026-06-12)
  local IPC threat model, settle DMG/PKG release posture, and harden critical
  workflow trust decisions.
- [x] **Phase 16: Release Validation Closure** - Run and record the final (completed 2026-06-12)
  public-release validation sequence, including exact blockers for anything that
  cannot be completed locally.

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
| 16. Release Validation Closure | v0.4 | 2/2 | Complete   | 2026-06-12 |

## Coverage

- Requirements mapped: 29/29
- Phases: 4
- Plans: 8 proposed
- Unmapped requirements: 0

---
*Roadmap updated: 2026-06-12 after v0.4 roadmap creation*
