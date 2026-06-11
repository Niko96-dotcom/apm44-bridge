# APM44 Bridge

## What This Is

APM44 Bridge is a macOS monitoring bridge for producers who want DAW sessions to
stay at 44.1 kHz while monitoring through USB-C AirPods Max at 48 kHz. It ships
as a menu bar app, a user-space resampler daemon, and a custom Core Audio HAL
driver that exposes an APM44 Bridge virtual output device upstream.

v0.1.1 established the shipped product path. v0.2 made that path reliable under
real daily lifecycle events: app errors, daemon exits, AirPods hotplug,
coreaudiod reloads, shared-memory ring recreation, and operator-facing recovery.

## Core Value

A producer can start monitoring once and trust Cubase at 44.1 kHz to keep
playing through USB-C AirPods at 48 kHz without silent wedges or mystery
relaunches.

## Current State (v0.2 shipped 2026-06-11)

**Shipped:** Reliability and Self-Healing milestone — 4 phases, 11 plans.

**What works now:**
- Deterministic app state machine: Start after errors, explicit Restart, user
  Stop distinct from crashes.
- Awaitable settings restarts that wait for real daemon termination.
- Always-on hotplug monitoring with bounded auto-retry and reconnecting UI.
- Daemon stale shared-memory ring detection (exit 42) with app-side recovery.
- Audit hardening: CLI idle loop, IOProc clamp, SPSC overrun, shm guards,
  seqlock metrics, stop escalation, HAL-truthful latency labels.
- Automated Swift and Catch2 regression suites for lifecycle and hardening paths.

**Known gaps (accepted at close):**
- QA-03 live operator checklist (hotplug smoke, Cubase HAL soak) pending hardware
  sign-off.
- IPC-04 installed build-ID agreement unproven until driver reinstall on target
  machine.
- `verify-installed-sync.sh` not yet CI-gated.

## Next Milestone Goals

Planning not started. Candidate themes from deferred items:
- PKG installer signing and DMG-first install without Terminal.
- Logic/Ableton validation matrix expansion.
- Support bundle export for operator diagnostics.
- Close QA-03 live verification and wire sync scripts into CI.

## Requirements

### Validated

- [x] DAW can route 44.1 kHz audio into the APM44 Bridge HAL virtual output
  device. — v0.1.0/v0.1.1
- [x] Daemon can read the HAL shared-memory ring and resample 44.1 -> 48 kHz for
  USB-C AirPods. — v0.1.0/v0.1.1
- [x] Menu bar app can select an output device, start the daemon in HAL mode, and
  show running metrics. — v0.1.0/v0.1.1
- [x] Public release flow can produce a signed/notarized DMG and a clean public
  repository surface. — v0.1.1
- [x] `scripts/verify-hal-driver.sh` and `apm44-bridge --shm-status` are the
  trusted live-driver verification entrypoints. — v0.1.1
- [x] Start from error state launches the bridge instead of silently doing
  nothing. — v0.2 (APP-01)
- [x] User Stop is tracked separately from unexpected daemon exits. — v0.2
  (APP-02)
- [x] Explicit Restart from running or error states. — v0.2 (APP-03–05)
- [x] Settings restarts await actual daemon termination. — v0.2 (REC-01)
- [x] Bounded auto-retry with backoff after unexpected exits. — v0.2 (REC-02)
- [x] Hotplug monitoring runs for app lifetime. — v0.2 (REC-03)
- [x] USB-C AirPods disconnect/reconnect recovery without DAW restart. — v0.2
  (REC-04, automated scope)
- [x] Virtual loopback devices excluded from output picker. — v0.2 (REC-05)
- [x] Daemon detects stale HAL shared-memory ring identity. — v0.2 (IPC-01–03)
- [x] Low-level audio/process hardening (AUD-01–07). — v0.2
- [x] Automated Swift transition tests (QA-01) and Catch2 hardening suite
  (QA-02). — v0.2

### Active

- [ ] Live installed-system proof: hotplug smoke, Cubase HAL soak, build-ID sync
  on operator hardware (QA-03, IPC-04 — deferred from v0.2 close).
- [ ] Commit and CI-gate `scripts/verify-installed-sync.sh`.

### Out of Scope

- LaunchAgent daemon auto-start — superseded for now by the menu bar app and
  Open at login.
- PKG installer signing — intentionally maintainer-only until installer signing
  is ready.
- Bluetooth-only AirPods reliability — USB-C AirPods Max is the product target
  for this bridge.
- Broad DAW expansion — Cubase 15 HAL path remains the validation anchor.
- Public repository planning artifacts — `.planning/` remains local/ignored
  unless explicitly force-added later.

## Context

- v0.2 closed with 22/24 requirements satisfied by automated evidence; QA-03 and
  IPC-04 accepted as operator-dependent gaps.
- Source integration points for reliability work:
  - `App/APM44Bridge/BridgeProcessManager.swift`
  - `App/APM44Bridge/HotplugMonitor.swift`
  - `BridgeDaemon/src/engine/VirtualDeviceFeed.cpp`
  - `Shared/src/MmapShmRing.cpp`
- `.planning/` is gitignored by default; selected artifacts are force-added for
  local GSD state.

## Constraints

- **Real-time audio:** No allocation, locks, blocking I/O, or expensive recovery
  inside Core Audio IO callbacks.
- **Core Audio lifecycle:** Device listeners and IOProcs must be registered and
  removed symmetrically; recovery should happen on non-real-time control paths.
- **HAL/shared memory:** The driver runs inside `coreaudiod`; the daemon must
  treat HAL restart/ring recreation as a normal lifecycle event.
- **Public repo posture:** Keep public docs user-facing. Internal GSD artifacts
  should remain ignored unless the user explicitly chooses to publish them.
- **Verification:** Live completion requires repo tests plus installed app/helper
  and installed driver synchronization; CI alone is not enough.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep v0.2 focused on reliability rather than new product surface | The shipped audio/DSP path is good; failures are lifecycle and recovery issues | ✓ Good — shipped lifecycle layer |
| Use app-level state-machine repair before adding auto-restart behavior | Auto-restart built on the current state transitions would inherit the same races | ✓ Good — StopReason + awaitable restart |
| Detect stale HAL shm in the daemon, not only in the UI | The UI cannot see when the daemon is draining an old unlinked mapping | ✓ Good — exit 42 + remap-once |
| Keep `.planning/` local/ignored for now | v0.1.1 intentionally made the repo public-facing and removed workbench artifacts | ✓ Good — unchanged |
| Accept QA-03/IPC-04 gaps at milestone close | Operator hardware and sudo driver reinstall required for live proof | ⚠️ Revisit — next milestone or ops task |
| macOS shm_dev=0 uses driver_generation for stale detection | st_ino unreliable on macOS shm objects | ✓ Good — Phase 7 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-06-11 after v0.2 Reliability and Self-Healing milestone*
