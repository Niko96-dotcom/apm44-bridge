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
- Complete **v1.0 Realtime Race Blocker Closure** - Phases 38-41 (shipped
  2026-06-14) - [archive](milestones/v1.0-ROADMAP.md)

## Current Status

v1.0 is shipped and archived. There is no active milestone. Start the next
milestone with `$gsd-new-milestone`.

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

## Completed Milestone Summaries

### v1.0 Realtime Race Blocker Closure

v1.0 closed the realtime race blockers identified in the 2026-06-14 audit.

- [x] Phase 38: Removed producer-side `DriftController` mutation from input
  overrun handling and published input overruns through a dedicated atomic
  counter.
- [x] Phase 39: Made `ShmIoHandler::ioRunning_` atomic across HAL start, stop,
  and mixed-output callbacks while preserving stopped-IO behavior.
- [x] Phase 40: Documented the libASPL serialized IO callback contract that
  makes mono-lane pending state safe, and added serialized left/right callback
  coverage.
- [x] Phase 41: Added source-audit regression guards, ran full repo CI, recorded
  installed-driver caveats, and reconciled traceability.

**Archive:** [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md),
[milestones/v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md),
[milestones/v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md),
[milestones/v1.0-phases/](milestones/v1.0-phases/)

## Verification Gates

- `scripts/ci.sh`
- Targeted native/source-audit tests for `BridgeInputOverrun`, `BridgeEngine`,
  `ShmIoHandler`, and mono-lane callback serialization
- `scripts/verify-installed-sync.sh --dry-run`
- `scripts/verify-hal-driver.sh` after the current driver is installed
- `apm44-bridge --shm-status` after the current HAL ring is live
- Target Cubase 15 and USB-C AirPods Max smoke/soak validation when hardware is
  available

## Next Step

Start the next milestone with `$gsd-new-milestone`.

---
*Last updated: 2026-06-14 after v1.0 milestone closeout*
