# Milestones: APM44 Bridge

## v0.2 Reliability and Self-Healing (Shipped: 2026-06-11)

**Phases completed:** 4 phases, 11 plans, 25 tasks

**Known deferred items at close:** 2 requirements accepted as gaps (see STATE.md Deferred Items)

**Key accomplishments:**

- StopReason tracking with injectable ProcessLaunching seam; start() recovers from error state
- Settings-driven restarts await real process termination; removed 300ms sleep race
- Restart button with stopping lockout, actionable errors, and 7 automated transition tests
- Core Audio hotplug monitoring now lives for the full app process lifetime
- Virtual loopback outputs excluded; bounded backoff retry with visible UI
- Shared IPC primitives detect recreated `/apm44_bridge_ring` via fstat identity and driver_generation
- Daemon polls stale shm on 500ms control tick, remaps once, exits 42 when recovery fails
- App treats exit 42 as recoverable; --shm-status and verify script prove helper/ring sync
- Blocking control loop, IOProc clamp, drop-oldest overrun, shm null guards, seqlock metrics
- Stop escalation with handler cleanup, HAL-truthful latency labels, Catch2 hardening suite
- CI green, installed-sync script, shm-status proof; hardware checklist awaiting operator

### Known Gaps (accepted at close)

- **QA-03**: Live hotplug smoke, Cubase HAL smoke, and 15+ min soak pending operator sign-off
- **IPC-04**: Installed build-ID agreement unproven until driver reinstall on target machine

---

## Completed

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

### v0.2 - Reliability and Self-Healing

**Shipped:** 2026-06-11

**Delivered:**
- Working app process state machine and deterministic restart behavior.
- Always-on hotplug/device recovery with bounded auto-retry.
- Daemon-side stale shared-memory ring detection and app-side relaunch (exit 42).
- Low-level callback, ring, process, and metrics hardening.
- Automated Swift and Catch2 regression suites; live verification checklist prepared.

**Archive:** [milestones/v0.2-ROADMAP.md](milestones/v0.2-ROADMAP.md), [milestones/v0.2-REQUIREMENTS.md](milestones/v0.2-REQUIREMENTS.md), [milestones/v0.2-MILESTONE-AUDIT.md](milestones/v0.2-MILESTONE-AUDIT.md)
