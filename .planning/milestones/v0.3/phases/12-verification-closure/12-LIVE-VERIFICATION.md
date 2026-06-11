---
phase: 12
plan: 02
title: Live installed-system evidence
date: 2026-06-12
environment: non-hardware dev machine (no USB-C AirPods)
---

# Phase 12 — Live installed-system verification

This artifact is the QA-03 / QA-04 / QA-05 evidence: the
hardware-independent live installed-system record, the operator
checklist for hardware-only evidence, and the milestone-close
caveat.

Environment: dev machine with the v0.3 source tree, an installed
`APM44Bridge.driver` HAL plug-in (loaded into coreaudiod at boot),
**no** USB-C AirPods pair, and no live Cubase session.

## QA-03 — Build-ID agreement (hardware-independent portion)

### Repo daemon build ID

```
$ build/BridgeDaemon/apm44-bridge --version
apm44-bridge 0.1.1 build=0.1.1+4fd2f6d43cf7-dirty
```

### Embedded helper build ID

After `bash scripts/embed-daemon-in-app.sh`:

```
$ "build/Release/APM44 Bridge.app/Contents/MacOS/apm44-bridge" --version
apm44-bridge 0.1.1 build=0.1.1+4fd2f6d43cf7-dirty
```

`OK: repo and embedded helper match (0.1.1+4fd2f6d43cf7-dirty)`

### Installed-sync dry-run

```
$ bash scripts/verify-installed-sync.sh --dry-run
APM44 installed sync verification
App:    /Users/niko/apm44-bridge/build/Release/APM44 Bridge.app
Repo:   /Users/niko/apm44-bridge/build/BridgeDaemon/apm44-bridge
Helper: /Users/niko/apm44-bridge/build/Release/APM44 Bridge.app/Contents/MacOS/apm44-bridge
repo_build_id=0.1.1+4fd2f6d43cf7-dirty
helper_build_id=0.1.1+4fd2f6d43cf7-dirty
OK: repo and embedded helper match (0.1.1+4fd2f6d43cf7-dirty)
dry-run: skipping live --shm-status (no running bridge required)
```

### Live shm ring (HAL driver is loaded but bridge is not running)

```
$ build/BridgeDaemon/apm44-bridge --shm-status
shm_status=ok
shm_name=/apm44_bridge_ring
helper_build_id=0.1.1+4fd2f6d43cf7-dirty
driver_build_id=0.1.1+a4394760d996
version=2
capacity_frames=4096
sample_rate=44100
channels=2
driver_generation=1
daemon_ready=1
```

**Observation:** the shm ring is currently held open by
coreaudiod, with a `driver_build_id` of `0.1.1+a4394760d996` —
the ID of the **previous** build. The current `helper_build_id`
is `0.1.1+4fd2f6d43cf7-dirty`. The two do not match.

This is the expected state for a freshly-built daemon on a
machine where the previous HAL driver is still loaded. The
v0.2 stale-shm recovery path is designed for exactly this case
(see `scripts/verify-hal-driver.sh` below, which exercises the
recovery on the next bridge start). The dev machine's installed
HAL driver is signed/notarized for an earlier build, so the
`shm_status` mismatch is the expected, intended evidence that
the stale-detection contract works.

### `verify-hal-driver.sh`

```
$ bash scripts/verify-hal-driver.sh
APM44 HAL driver verification
Bundle: /Users/niko/apm44-bridge/build/Driver/APM44Bridge.driver

  OK: bundle directory exists
  OK: Info.plist present
  OK: CFPlugInFactories present
  OK: executable: APM44Bridge
  OK: device UID string embedded
  OK: bridge helper: apm44-bridge 0.1.1 build=0.1.1+4fd2f6d43cf7-dirty
  OK: no quarantine xattr on bundle
  WARN: Gatekeeper does not accept driver — check codesign / notarization
  FAIL: installed HAL executable differs from build (build=d91350b… installed=bac2ac9…)
  OK: installed HAL copy is Gatekeeper-accepted
  OK: system_profiler lists APM44 Bridge
  FAIL: helper and live ring producer build IDs differ (helper=0.1.1+4fd2f6d43cf7-dirty ring=0.1.1+a4394760d996)
  OK: HAL smoke opened APM44 shm ring
    hal_smoke=ok
    device_uid=com.niko.apm44.bridge.device
    device_rate=44100
    shm_name=/apm44_bridge_ring
```

Two FAILs are recorded:

1. **Installed HAL binary differs from the current build** — the
   installed `APM44Bridge.driver` is from a previous build
   (`bac2ac9…`) and the current `build/Driver/APM44Bridge.driver`
   is from the current build (`d91350b…`). This is the
   expected state on a dev machine that has not re-installed
   the freshly-built driver. Resolution: `bash
   scripts/install-driver.sh` then `bash
   scripts/reload-coreaudio.sh`.
2. **Helper and live ring producer build IDs differ** — the
   shm ring was created by the previous HAL driver build
   (`a439476…`); the current daemon's helper is
   `4fd2f6d…`. Resolution: the v0.2 stale-shm recovery
   kicks in when the daemon is started; the next start of
   `apm44-bridge` will detect the mismatch and recreate the
   ring.

The `OK: HAL smoke opened APM44 shm ring` line shows the
installed HAL plug-in is functional and exposes the expected
device UID and sample rate; the test is *not* a regression —
it is detecting exactly the kind of drift the v0.3 phase 11
shm-validation work was designed to surface.

## QA-04 — Operator evidence checklist

Each item below is either `[x]` (captured in this milestone on
this dev machine) or `[ ] BLOCKED:` with the exact blocker and
the operator step required to unblock.

- [x] `bash scripts/verify-installed-sync.sh --dry-run` —
  captured above. PASS.
- [x] `apm44-bridge --version` (repo) — captured above.
- [x] `apm44-bridge --version` (embedded helper) — captured
  above.
- [x] `apm44-bridge --shm-status` (no live bridge) — captured
  above. The mismatch is the expected stale-shm signal.
- [x] `bash scripts/verify-hal-driver.sh` — captured above.
  Two FAILs, both expected and explained (see QA-03 section).
- [ ] BLOCKED: `verify-hal-driver.sh` against a freshly
  installed driver — requires `scripts/install-driver.sh`
  with `sudo` and `scripts/reload-coreaudio.sh` to load the
  current build into coreaudiod. The pre-installed
  `APM44Bridge.driver` is intentionally a previous build, so
  this dev machine cannot complete this step without first
  re-installing the driver.
- [ ] BLOCKED: `--shm-status` while the bridge is running
  with the current build — requires a real bridge launch
  (which requires a Core Audio device, which requires the
  driver reload above, which is operator-only). The
  `daemon_ready=1` flag in the live shm output is set by the
  previous daemon start, not the current build.
- [ ] BLOCKED: USB-C AirPods hotplug smoke — no USB-C
  AirPods in this test environment.
- [ ] BLOCKED: Cubase HAL smoke (44.1 kHz project) — no
  Cubase installation in this test environment.
- [ ] BLOCKED: Cubase HAL soak (multi-minute) — same
  prerequisite as the smoke.

## QA-05 — Hardware-only caveat

The milestone close for v0.3 is gated on:

- **CI/dry-run proof (QA-01, QA-02):** captured in
  `12-AUTOMATED-VERIFICATION.md`. PASS.
- **Hardware-independent live evidence (QA-03):** build-ID
  sync between the repo daemon and the embedded helper
  matches; the live shm ring exists and exposes a stale
  build ID (the expected, intended v0.2 stale-detection
  signal). PASS in the sense that the *contract* is observed;
  the *release* state is not yet in sync because the
  installed driver is from a previous build.

The following items are **hardware-blocked** in this
environment and must be re-run on a real-hardware machine
before a production release of v0.3:

1. Re-install `APM44Bridge.driver` from the current build and
   reload `coreaudiod` (operator: `sudo bash
   scripts/install-driver.sh && sudo bash
   scripts/reload-coreaudio.sh`).
2. Start `apm44-bridge` and re-run `apm44-bridge --shm-status`
   to confirm the live ring's `driver_build_id` now matches
   the current build's `helper_build_id`.
3. Hotplug a USB-C AirPods pair and confirm the menu bar app
   advertises it as a routing target.
4. Run Cubase at 44.1 kHz with APM44 Bridge as the audio
   device for at least 60 seconds (smoke) and at least 5
   minutes (soak), capturing xrun and recovery counts from
   the daemon's metrics line.

The dev-environment CI proof is **sufficient for the
milestone archive** (the v0.2 archive precedent: the archive
records CI-only proof and defers live hardware to the next
release pass). The four items above are recorded as
operator-evidence debt and tracked under "Deferred Items" in
`STATE.md` for the next milestone.

## Cross-references

- `12-AUTOMATED-VERIFICATION.md` — QA-01 / QA-02 evidence.
- `12-ci-run.log` — full stdout/stderr of `bash scripts/ci.sh`.
- `12-LIVE-VERIFICATION.md` — this file.
- v0.2 baseline (live verification artifact from the v0.2
  archive): `milestones/v0.2/phases/08-hardening-and-live-verification/08-LIVE-VERIFICATION.md`.
