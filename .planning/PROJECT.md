# APM44 Bridge

## What This Is

APM44 Bridge is a macOS monitoring bridge for producers who want DAW sessions to
stay at 44.1 kHz while monitoring through USB-C AirPods Max at 48 kHz. It ships
as a menu bar app, a user-space resampler daemon, and a custom Core Audio HAL
driver that exposes an APM44 Bridge virtual output device upstream.

v0.1.1 established the shipped product path. v0.2 made that path reliable under
real daily lifecycle events: app errors, daemon exits, AirPods hotplug,
coreaudiod reloads, shared-memory ring recreation, and operator-facing recovery.
v0.3 hardened the realtime callback, process-stop, metrics, and shared-memory
validation paths with automated regression coverage before returning to public
release packaging.

## Core Value

A producer can start monitoring once and trust Cubase at 44.1 kHz to keep
playing through USB-C AirPods at 48 kHz without silent wedges or mystery
relaunches.

## Current State (v0.3 shipped 2026-06-12)

**Shipped:** Realtime Audio Hardening milestone — 4 phases, 8 plans.

**What works now:**
- v0.2 deterministic app lifecycle, restart, hotplug, and stale-ring recovery.
- Realtime SPSC ownership is preserved under input overrun; new input is dropped
  without producer-side consumption.
- Oversized interleaved and non-interleaved output callbacks render or silence
  every Core Audio frame.
- Swift process-stop waiters complete independently and escalation reaches the
  timeout path.
- Metrics publication no longer relies on bare cross-thread `MetricsSnapshot`
  copies.
- Shared-memory opening rejects truncated, lying, or corrupt mappings before
  trusting capacity or build-ID strings.
- `scripts/ci.sh` includes the installed-sync dry-run gate.

**Known gaps (accepted at close):**
- QA-03 live installed-system build-ID sync remains partial until driver
  reinstall on real hardware.
- QA-04 live operator evidence remains hardware-blocked: USB-C AirPods hotplug,
  Cubase HAL smoke, and Cubase soak.

## Current Milestone: v0.4 Public Release Blocker Closure

**Goal:** Close the publishing blockers in the attached review so the next
public release is strict, race-free, and professionally shippable.

**Target features:**
- Make `MetricsPublisher` C++ data-race-free and ThreadSanitizer-clean.
- Fix `BridgeMetrics::ToJsonLine` truncation safety with regression coverage.
- Harden Core Audio failure paths: virtual-device output-start cleanup and
  non-interleaved input buffer sizing.
- Make notarization, signing, and release automation fail hard unless explicitly
  opted out.
- Document the local shared-memory threat model and remove misleading or dead
  realtime helpers.
- Recheck distribution UX: DMG stapling order, signed PKG direction, and
  SHA-pinned release workflows.
- Add blocker-list regression tests and run a clean release validation sequence.

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
- [x] Realtime callback ownership and oversized output callback handling. —
  v0.3 (RT-01–05)
- [x] Process-stop waiter and escalation hardening. — v0.3 (PROC-01–04)
- [x] Metrics publication no longer uses bare cross-thread snapshot copies. —
  v0.3 (METR-01–03)
- [x] Shared-memory validation rejects malformed mappings and bounded build-ID
  diagnostics. — v0.3 (SHM-01–05)
- [x] Installed-sync dry-run is CI-gated and automated hardening evidence is
  captured. — v0.3 (QA-01, QA-02, QA-05)

### Active

- [ ] Metrics publication is demonstrably data-race-free under standard C++ and
  ThreadSanitizer.
- [ ] Metrics JSON serialization cannot read past its fixed stack buffer when
  output is truncated.
- [ ] Core Audio virtual-device and non-interleaved callback error paths fail
  safely without null IOProc cleanup or buffer overreads.
- [ ] Release scripts and signing workflows fail closed for notarization and app
  build failures unless an explicit local-development override is set.
- [x] Shared-memory mode `0666` has a clear public threat model and no security
  overclaiming.
- [ ] Realtime helper names/comments match actual drop-new behavior; unused
  silence helpers are deleted or corrected.
- [x] Public distribution path documents or implements professional installer
  expectations: stapled inner artifacts, strict DMG notarization, and signed PKG
  direction.
- [x] Release GitHub Actions near credentials/artifacts are pinned or explicitly
  tracked as a release-hardening decision.
- [ ] Public-release regression and validation gates cover all blocker fixes.

### Out of Scope

- LaunchAgent daemon auto-start — superseded for now by the menu bar app and
  Open at login.
- Bluetooth-only AirPods reliability — USB-C AirPods Max is the product target
  for this bridge.
- Broad DAW expansion — Cubase 15 HAL path remains the validation anchor.
- New DSP/resampler architecture — v0.4 is about release-blocking correctness
  and distribution hardening, not audio-engine replacement.
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
- v0.4 is seeded from the "Blockers before publishing" review attached on
  2026-06-12. It focuses on release-blocking correctness, security posture, and
  packaging automation, not new audio/DSP features.
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
| Treat v0.4 as public-release blocker closure before publishing | The attached blocker review identifies correctness, release automation, and security-posture issues that should not ship silently | — Pending |
| Keep v0.4 DMG-primary for public distribution | The DMG install flow is already shipped and can be made honest/professional now; PKG-primary needs Developer ID Installer validation before becoming public | ✓ Good — PKG remains maintainer-only/future |
| GitHub Actions trust decision for v0.4 | Official actions remain tag-pinned with Dependabot monitoring; full-length SHA pinning becomes required before moving more signing/notarization/release publication into CI | ✓ Good — documented release-hardening decision |

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
*Last updated: 2026-06-12 after v0.4 Public Release Blocker Closure milestone start*
