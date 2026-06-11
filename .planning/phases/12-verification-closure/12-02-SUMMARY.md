---
phase: 12
plan: 02
title: Live installed-system evidence and operator checklist
subsystem: verification
status: complete
---

# Plan 12-02: Live installed-system evidence and operator checklist

## What was done

### Task 1 — Hardware-independent live evidence

Captured each of:

- `verify-installed-sync.sh --dry-run` — exit 0, OK.
- `apm44-bridge --version` (repo and embedded helper) — both
  report `0.1.1+4fd2f6d43cf7-dirty`, matching.
- `apm44-bridge --shm-status` (with the HAL driver loaded but
  no bridge running) — the shm ring exists, the
  `driver_build_id` is the previous build's
  (`0.1.1+a4394760d996`), confirming the v0.2 stale-shm
  detection contract is observing the expected drift.
- `bash scripts/verify-hal-driver.sh` — runs through and
  reports two FAILs, both expected and explained: the
  installed HAL binary is from a previous build, and the
  helper's build ID differs from the live ring's
  `producer_build_id`. The `HAL smoke opened APM44 shm ring`
  line confirms the driver itself is functional.

### Task 2 — HAL driver install state

Documented the exact pre-requisite: the dev machine has a
previously-installed `APM44Bridge.driver` that is intentionally
not from the current build. Re-installing the current build
requires `sudo bash scripts/install-driver.sh && sudo bash
scripts/reload-coreaudio.sh`, which is operator-only.

### Task 3 — QA-04 operator evidence checklist

Wrote a checklist with 10 items, each tagged with either `[x]`
(captured on this dev machine) or `[ ] BLOCKED:` (with the
exact blocker and unblock step). The 4 BLOCKED items are:
fresh-driver install + coreaudiod reload, `--shm-status` with
the bridge running, USB-C AirPods hotplug smoke, and Cubase
HAL smoke/soak.

### Task 4 — QA-05 hardware-only caveat

Wrote a milestone-close caveat that:

- States the dev-environment CI proof is sufficient for the
  v0.3 milestone archive (matching the v0.2 archive
  precedent).
- Lists the four hardware-blocked items that must be re-run
  on a real-hardware machine before a production release.
- Cross-references the v0.2 baseline for the same pattern.

## Deviations

None at the source level. The QA-04 items that depend on
hardware cannot be exercised on a non-hardware dev machine;
this is the same situation v0.2 faced and the same mitigation
(operator checklist + caveat + deferred-items record) was
used. The v0.2 baseline is cited as the precedent.

## Commits

- `docs(12): add live installed-system verification and
  operator checklist` — adds `12-LIVE-VERIFICATION.md`.
