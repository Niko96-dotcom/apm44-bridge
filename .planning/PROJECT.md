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

## Current Milestone: v0.3 Realtime Audio Hardening

**Goal:** Make the realtime audio, process-stop, metrics, and shared-memory
paths race-free and defensive before expanding packaging or DAW coverage.

**Target features:**
- Preserve the `PlanarRingBuffer` single-producer / single-consumer contract by
  removing producer-side consumer behavior or moving oldest-frame dropping to the
  output side.
- Ensure output callbacks larger than the internal scratch size render or
  silence every frame.
- Make Swift process-stop waiting timeout-safe, escalation-safe, and safe for
  concurrent waiters.
- Publish bridge metrics through a C++ data-race-free path.
- Reject truncated, inconsistent, or corrupt shared-memory mappings before any
  ring read/write path trusts header capacity or build-ID strings.
- Close deferred installed-system proof: QA-03 live DAW/hotplug soak, IPC-04
  build-ID sync, and CI-gating for `verify-installed-sync.sh`.

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

- [ ] Realtime ring ownership: `PlanarRingBuffer` remains SPSC under overrun and
  normal callback flow.
- [ ] Output callback coverage: every Core Audio output frame is rendered or
  explicitly silenced, including callbacks larger than scratch buffers.
- [ ] Stop escalation: timed-out process termination reliably reaches SIGKILL
  and concurrent termination waiters do not overwrite each other.
- [ ] Metrics publication: UI metrics snapshots are C++ data-race-free.
- [ ] Shared-memory validation: malformed/truncated shm objects and unterminated
  build-ID fields are rejected or safely described.
- [ ] Live installed-system proof: hotplug smoke, Cubase HAL soak, build-ID sync
  on operator hardware (QA-03, IPC-04 - deferred from v0.2 close).
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
  - `BridgeDaemon/src/engine/BridgeInputOverrun.h`
  - `BridgeDaemon/src/IoProcHandlers.cpp`
  - `BridgeDaemon/src/engine/BridgeEngine.*`
  - `App/APM44Bridge/BridgeProcessManager.swift`
  - `App/APM44Bridge/HotplugMonitor.swift`
  - `BridgeDaemon/src/engine/VirtualDeviceFeed.cpp`
  - `Shared/src/MmapShmRing.cpp`
  - `Shared/src/ShmObjectIdentity.*`
- v0.3 was seeded from a focused highest-priority bug/risk review covering SPSC
  ring ownership, large callbacks, stop-timeout continuation handling, metrics
  races, and shm mapping validation.
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
| Treat v0.3 as hardening before feature expansion | The attached risk list points to correctness issues in realtime and IPC paths | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? Move to Out of Scope with reason.
2. Requirements validated? Move to Validated with phase reference.
3. New requirements emerged? Add to Active.
4. Decisions to log? Add to Key Decisions.
5. "What This Is" still accurate? Update if drifted.

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections.
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state.

---
*Last updated: 2026-06-12 after v0.3 Realtime Audio Hardening milestone start*
