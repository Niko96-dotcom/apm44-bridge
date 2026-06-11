---
phase: 12
title: Verification Closure
status: planning
---

# Phase 12 Context: Verification Closure

## Phase goal (from ROADMAP)

v0.3 closes with **automated hardening evidence and live
installed-system proof, or with precise hardware blockers
recorded**. The phase is the final gate before the milestone is
declared shippable; it covers the last of QA-01..QA-05.

## Requirements

| Req | Description | Where it lives |
| --- | --- | --- |
| QA-01 | `scripts/ci.sh` runs a non-hardware dry-run check of `scripts/verify-installed-sync.sh`. | plan 12-01 |
| QA-02 | Final automated verification covers secret scan, CMake/Catch2, Swift build/tests, and installed-sync dry-run. | plan 12-01 |
| QA-03 | Live verification records repo daemon, embedded app helper, installed HAL driver, and live shm ring build-ID agreement, or the exact blocker. | plan 12-02 |
| QA-04 | Operator evidence covers `verify-hal-driver.sh`, `--shm-status`, USB-C AirPods hotplug smoke, and Cubase HAL smoke/soak where hardware is available. | plan 12-02 |
| QA-05 | Milestone close records any remaining hardware-only caveat instead of treating CI-only proof as complete. | plan 12-02 + lifecycle |

## Grey areas and decisions

### GA-12-01 — Should `ci.sh` fail if `verify-installed-sync.sh --dry-run` is not a clean dry-run?

The current `verify-installed-sync.sh --dry-run` succeeds when the
embedded helper is missing (it logs `WARN: embedded helper
missing — run scripts/embed-daemon-in-app.sh` and exits 0). In CI,
the app helper will not exist because the Swift app is not built
in the same run that builds the daemon (or the app build runs
first, but the helper is not re-embedded).

**Decision:** treat the dry-run as a contract check, not a fail
gate. CI must show the WARN, not pass silently, but the exit code
is 0 with the WARN. This matches the existing script semantics
and keeps the test useful for surfacing missing-embed drift.

### GA-12-02 — How to capture live evidence on a non-hardware dev machine

The dev machine used for this milestone has no USB-C AirPods and
no installed HAL driver that this repo owns. The live evidence
record must therefore be split into:

- "what we *can* run here" (repo daemon, embedded helper, app
  bundle) — executable and produced.
- "what is *blocked by hardware*" — listed with the exact blocker
  (no USB-C AirPods in test environment, no installed HAL
  driver). This is the QA-05 caveat.

The plan produces two artifacts:

1. `12-AUTOMATED-VERIFICATION.md` — the CI/dry-run output.
2. `12-LIVE-VERIFICATION.md` — the live installed-system record
   with explicit hardware-blocker sections.

### GA-12-03 — Is the operator evidence step interactive?

QA-04 is operator-driven and depends on real hardware. We can
**document the operator checklist** with the exact commands and
expected outputs, but we cannot execute it on a non-hardware dev
machine. The plan records the checklist and the partial-execution
result (commands that succeed without hardware are run; commands
that need hardware are listed with their exact prerequisite).

## Plan shape

- **Plan 12-01** (QA-01, QA-02): update `scripts/ci.sh` to invoke
  `verify-installed-sync.sh --dry-run` after the Swift build, then
  run the full local CI gate and capture the output.
- **Plan 12-02** (QA-03, QA-04, QA-05): run the
  hardware-independent live verification commands
  (daemon, embedded helper, app bundle, dry-run shm), record the
  results, and write `12-LIVE-VERIFICATION.md` with explicit
  hardware-blocker sections for the parts that need a USB-C
  AirPods pair and an installed HAL driver.

## Dependencies

- Phase 11 (SHM validation hardening) must be complete — the
  `--shm-status` output and the shm ID comparison are part of
  live verification.
- The 20 ctest targets and 42 Swift tests must still pass.
- `scripts/embed-daemon-in-app.sh` must run successfully to
  produce the embedded helper.

## Out of scope

- Real audio quality measurements (RT-xrun counts, dropout rates)
  — those need Cubase + AirPods and are QA-04 operator evidence.
- Build ID signing / notarization — those are v0.1.1 concerns, not
  in the v0.3 scope.
- Packaging a signed PKG installer — deferred to a future
  milestone.

## Success criteria recap

(All from the ROADMAP.)

1. `scripts/ci.sh` includes a non-hardware dry-run check for
   `scripts/verify-installed-sync.sh`.
2. Final automated verification includes secret scan, CMake/Catch2
   tests, Swift app build/tests, and installed-sync dry-run.
3. Live verification records repo daemon, embedded app helper,
   installed HAL driver, and live shm ring build-ID agreement, or
   the exact blocker.
4. Operator evidence covers `verify-hal-driver.sh`, `--shm-status`,
   USB-C AirPods hotplug smoke, and Cubase HAL smoke/soak where
   hardware is available.
5. Milestone close records any remaining hardware-only caveat
   instead of treating CI-only proof as complete.
