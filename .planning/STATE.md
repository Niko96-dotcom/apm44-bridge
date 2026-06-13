---
gsd_state_version: 1.0
milestone: v0.6
milestone_name: Public Release Safety Fixes
status: planning
last_updated: "2026-06-13T16:08:44.654Z"
last_activity: 2026-06-13
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-13)

**Core value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

**Current focus:** v0.5 Release Readiness Hardening milestone complete and cleaned up; awaiting operator review, release tag decision, and next milestone definition

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-06-13 — Milestone v0.6 started

## Performance Metrics

**Velocity (v0.5):**

- Total plans completed: 8
- Phases: 17-22 (6 phases)
- Timeline: 2026-06-13
- 16/16 requirements satisfied by automated evidence or live release validation proof
- Signed/notarized DMG path validated end-to-end and accepted by Gatekeeper

**Velocity (v0.4):**

- Total plans completed: 8
- Phases: 13-16 (4 phases)
- Timeline: 2026-06-12 (single-day execution)
- 29/29 requirements satisfied by automated evidence or recorded release
  validation proof

- Public artifact path validated as DMG-first; PKG remains future/maintainer-only

**Velocity (v0.3):**

- Total plans completed: 8
- Phases: 9-12 (4 phases)
- Timeline: 2026-06-12 (single-day execution)
- 20/22 requirements satisfied by automated evidence
- 2/22 accepted gaps: QA-03, QA-04 (both hardware-blocked on dev machine)

**Velocity (v0.2):**

- Total plans completed: 11
- Phases: 5-8 (4 phases)
- Timeline: 2026-06-11 (single-day execution)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

- v0.2: Keep milestone focused on lifecycle reliability, not new DSP or
  packaging scope.

- v0.2: Fix the app state machine before adding auto-restart behavior.
- v0.2: Treat installed app/helper/driver/live ring synchronization as part of
  completion.

- Phase 7: macOS shm uses driver_generation when st_ino is zero for stale detection.
- Phase 7: Daemon exit 42 + `stale shm ring` stderr for app recoverable classification.
- Milestone close: Accepted QA-03 and IPC-04 gaps as operator-dependent tech debt.
- v0.3: Keep scope to realtime callback safety, process/metrics races, shm
  validation, and proof closure before packaging or DAW expansion.

- v0.3 Phase 9: Producer overrun policy is "drop new input" (RT-02). Oldest-frame
  trimming remains an output-consumer responsibility only.

- v0.3 Phase 10: Metrics publication uses a seqlock on a standalone
  MetricsPublisher type; the source-level regression guard
  `NoBareMetricsSnapshotCopyInSource` enforces no plain `MetricsSnapshot`
  copies.

- v0.3 Phase 11: macOS shm page-rounding prevents functional exercise of the
  `HeaderTruncated` and live size-change checks on this platform; source-level
  guard tests assert the invariants.

- v0.3 Phase 12: First CI run with the new dry-run gate caught a real
  build-ID drift between repo daemon and embedded helper; re-embedded via
  `scripts/embed-daemon-in-app.sh` and CI went green.

- v0.5: Second pass on release-readiness blockers. The provided blocker review
  overlaps with v0.4 but is treated as the authoritative scope for this milestone;
  any already-fixed items will be verified and regression-gated.

- Phase 20: Existing docs and code already satisfied SEC-01/02/03; the phase
  added requirement tags and a source-level guard test rather than behavioral
  changes.

- Phase 22: Full local CI gate passed (20 native + 43 Swift tests, release
  script regression tests, installed-sync dry-run). Apple credentials were
  available, so the signed/notarized DMG path was run clean and produced a
  Gatekeeper-accepted artifact. QA-01 and QA-02 are satisfied by live evidence.

### Pending Todos

None.

### Blockers/Concerns

None. v0.5 milestone is complete.

- Milestone audit completed 2026-06-13: `.planning/v0.5-MILESTONE-AUDIT.md` status `tech_debt`. No blockers; minor planning-hygiene gaps and accepted operational caveats are documented in the audit.

## Deferred Items

Items acknowledged and deferred at milestone close:

| Category | Item | Status |
|----------|------|--------|
| publication | GitHub release publication/upload for the final DMG | operator action |
| packaging | Signed PKG installer | future/maintainer-only |
| live soak | USB-C AirPods/Cubase validation on target hardware | operator-dependent |
| requirement | v0.2 QA-03 live DAW soak | deferred (carried from v0.2) |
| requirement | v0.2 IPC-04 installed build-ID sync | partial (carried from v0.2) |
| requirement | v0.3 QA-03 live installed-system build-ID sync | partial (hardware-blocked; repo+helper sync captured, full sync requires driver reinstall) |
| requirement | v0.3 QA-04 live operator evidence (hotplug smoke, Cubase smoke/soak) | deferred (hardware-blocked) |
| integration | No spawn-level exit-42 E2E test | deferred |
| integration | performRestart during disconnect-wait untested | deferred |
| live soak | Cubase HAL soak after coreaudiod reload | deferred |
| packaging | Signed PKG installer | future |
| compatibility | Logic/Ableton validation matrix | future |
| observability | Support bundle export | future |

## Session Continuity

Last session: 2026-06-13T17:15:00.000Z
Stopped at: v0.5 milestone cleanup complete; phases 17-22 archived to .planning/milestones/v0.5/phases/
Resume file: None

## Operator Next Steps

- Review v0.5 milestone audit (`.planning/v0.5-MILESTONE-AUDIT.md`) and closeout artifacts:
  - `.planning/milestones/v0.5-SUMMARY.md`
  - `.planning/milestones/v0.5-ROADMAP.md`
  - `.planning/milestones/v0.5-REQUIREMENTS.md`
  - `.planning/PROJECT.md` (Current State and Key Decisions updated)
  - `.planning/STATE.md` (milestone completion recorded)
- Decide whether to tag `v0.5.0` and publish the signed/notarized DMG (`build/signing/APM44Bridge-0.1.1.dmg`).
- Optional: run live USB-C AirPods Max / Cubase soak on target hardware before public release.
- Start next milestone planning (`/gsd-new-milestone`) when ready.
