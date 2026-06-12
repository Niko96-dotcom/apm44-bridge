# Milestones: APM44 Bridge

## Completed

### v0.4 - Public Release Blocker Closure

**Shipped:** 2026-06-12
**Phases completed:** 4 phases, 8 plans, 29 requirements

**Delivered:**

- Atomic metrics publication and fail-closed metrics JSON serialization with targeted Catch2 regression coverage.
- Core Audio callback edge cases are bounded, and the realtime overrun helper now truthfully names drop-new-input behavior.
- Release notarization scripts and `release-all.sh` fail closed by default, with credential-free notary regression tests.
- Public docs now explain the local IPC threat model, DMG-primary install posture, and GitHub Actions trust decision.
- Final DMG-primary release validation succeeded with Developer ID signing, app/driver and DMG notarization, stapling, and Gatekeeper acceptance.
- Repeatable release-validation documentation records exact commands, artifact assessment, checksum, and remaining operator-owned caveats.

**Known caveats at close:**

- GitHub release publication/upload remains an operator action for the current public artifact.
- Signed PKG packaging remains future/maintainer-only; public distribution stays DMG-first.
- Live USB-C AirPods/Cubase soak remains operator-dependent and outside local automation.

**Archive:** [milestones/v0.4-ROADMAP.md](milestones/v0.4-ROADMAP.md), [milestones/v0.4-REQUIREMENTS.md](milestones/v0.4-REQUIREMENTS.md), [milestones/v0.4-MILESTONE-AUDIT.md](milestones/v0.4-MILESTONE-AUDIT.md)

### v0.3 - Realtime Audio Hardening

**Shipped:** 2026-06-12
**Phases completed:** 4 phases, 8 plans, 22 requirements

**Delivered:**

- Enforced the single-producer/single-consumer realtime callback contract and explicit drop-new-input overrun policy.
- Fixed oversized output callbacks so stale tail samples are silenced for interleaved and non-interleaved buffers.
- Closed concurrent termination waiter races and strengthened stop/restart timeout coverage.
- Published daemon metrics through a seqlock-backed `MetricsPublisher` with stress and source-level guard tests.
- Hardened shared-memory validation for truncated headers, lying capacities, object identity drift, and bounded build-ID diagnostics.
- Added the installed-sync dry-run CI gate that caught and fixed a real embedded-helper build-ID drift.

**Known caveats at close:**

- Live installed-system build-ID proof and Cubase/AirPods operator evidence remained hardware-blocked.

**Archive:** [milestones/v0.3-ROADMAP.md](milestones/v0.3-ROADMAP.md), [milestones/v0.3-REQUIREMENTS.md](milestones/v0.3-REQUIREMENTS.md), [milestones/v0.3-MILESTONE-AUDIT.md](milestones/v0.3-MILESTONE-AUDIT.md), [milestones/v0.3-SUMMARY.md](milestones/v0.3-SUMMARY.md)

### v0.2 - Reliability and Self-Healing

**Shipped:** 2026-06-11
**Phases completed:** 4 phases, 11 plans, 25 tasks

**Delivered:**

- StopReason tracking with injectable ProcessLaunching seam; `start()` recovers from error state.
- Settings-driven restarts await real process termination and removed the 300 ms sleep race.
- Restart button with stopping lockout, actionable errors, and 7 automated transition tests.
- Core Audio hotplug monitoring now lives for the full app process lifetime.
- Virtual loopback outputs excluded; bounded backoff retry with visible UI.
- Shared IPC primitives detect recreated `/apm44_bridge_ring` via fstat identity and driver_generation.
- Daemon polls stale shm on a 500 ms control tick, remaps once, and exits 42 when recovery fails.
- App treats exit 42 as recoverable; `--shm-status` and verify script prove helper/ring sync.
- Blocking control loop, IOProc clamp, drop-oldest overrun, shm null guards, seqlock metrics.
- Stop escalation with handler cleanup, HAL-truthful latency labels, and Catch2 hardening suite.
- CI green, installed-sync script, shm-status proof; hardware checklist awaiting operator.

**Known gaps at close:**

- **QA-03:** Live hotplug smoke, Cubase HAL smoke, and 15+ minute soak pending operator sign-off.
- **IPC-04:** Installed build-ID agreement unproven until driver reinstall on target machine.

**Archive:** [milestones/v0.2-ROADMAP.md](milestones/v0.2-ROADMAP.md), [milestones/v0.2-REQUIREMENTS.md](milestones/v0.2-REQUIREMENTS.md), [milestones/v0.2-MILESTONE-AUDIT.md](milestones/v0.2-MILESTONE-AUDIT.md)

### v0.1.0 - Initial signed distribution path

**Shipped:** 2026-06-01

**Delivered:**

- HAL virtual output device for 44.1 kHz DAW sessions.
- User-space bridge daemon with 44.1 -> 48 kHz sample-rate conversion and drift
  control.

- Swift menu bar app with virtual-device mode, latency presets, and first-run
  preflight checks.

- Release scripts for Developer ID signing, notarization, DMG, and PKG builds.

### v0.1.1 - Public release cleanup and HAL dropout fixes

**Shipped:** 2026-06-03

**Delivered:**

- Fixed HAL virtual-device dropout recovery and virtual-source drift tracking.
- Clarified menu metrics by separating hard xruns from recoveries.
- Recorded Cubase 15 operator sign-off and 30+ minute soak completion.
- Made the public release path DMG-first; PKG tooling remains maintainer-only.
- Pruned internal planning files from the public repository.
