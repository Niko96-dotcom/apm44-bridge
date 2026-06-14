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

## Current State (v0.8 shipped 2026-06-13)

**Validated:** v0.8 Release Candidate Closure milestone shipped 2026-06-13.
All fourteen v0.8 requirements are satisfied by automated release-candidate
evidence or recorded operator validation commands. The public release path now
has fail-closed manual signing credentials, HAL driver build coverage in the
manual signing workflow, strict driver-only notarization handling, current
release docs, distinct SRC quality behavior, and final release-Mac plus
target-hardware validation instructions.

**What works now:**
- v0.2 deterministic app lifecycle, restart, hotplug, and stale-ring recovery.
- Realtime SPSC ownership is preserved under input overrun; new input is dropped
  without producer-side consumption.
- Oversized interleaved and non-interleaved output callbacks render or silence
  every Core Audio frame.
- Swift process-stop waiters complete independently and escalation reaches the
  timeout path.
- Metrics publication is data-race-free under standard C++ and
  ThreadSanitizer-clean (`MetricsPublisher` atomic-field seqlock).
- `BridgeMetrics::ToJsonLine` handles `snprintf` truncation safely and cannot
  read past its stack buffer.
- Core Audio failure paths fail safely: virtual-device output-start cleanup only
  stops an input IOProc that was actually started, and non-interleaved input
  callbacks clamp both channel buffer sizes.
- Shared-memory opening rejects truncated, lying, or corrupt mappings before
  trusting capacity or build-ID strings.
- `scripts/ci.sh` includes the installed-sync dry-run gate.
- Release automation fails closed for notarization and app-build verification
  unless an explicit local-development override is set, with v0.6 source guards
  ensuring release-script tests remain in GitHub CI.
- The public DMG is built from stapled inner app/driver artifacts, then
  notarized/stapled; release-facing GitHub Actions trust posture is documented
  and regression-gated.
- The v0.5 public artifact path has live local evidence: Developer ID signing,
  app/driver evidence zip notarization, inner app/driver stapling and validation,
  final DMG notarization/stapling/validation, and Gatekeeper acceptance.
- HAL mono-lane timestamp pairing fails closed for unrelated mismatches while
  preserving the narrow rollover-tolerant pairing case.
- Mixed-output HAL processing ignores callbacks while IO is stopped.
- The unsafe legacy AudioToolbox converter public comparison path is removed.
- Realtime metrics floating payloads are stored through packed atomic integer
  representation rather than possibly-locking floating atomics.
- Device catalog refresh and app idle transitions no longer hang or show stale
  metrics state in the v0.6 audited paths.
- Manual signing workflow, `scripts/sign-release.sh`,
  `scripts/codesign-verify-release.sh`, and local CI agree on the Release app
  bundle path used for embedding, signing, and verification.
- Release codesign verification fails on weak signing posture unless an explicit
  local-development override is set.
- Metrics packed `std::atomic<uint64_t>` storage has compile-time lock-free
  proof, and clean running-process termination routes through the central idle
  reset path.
- Manual signing workflow builds both `apm44-bridge` and `APM44Bridge` before
  signing, and missing `APPLE_SIGN_ID` / `AC_NOTARY` inputs fail the workflow
  instead of silently skipping.
- Driver-only notarization uses the shared strict accepted-status helper and
  keeps stapling/validation after accepted notarization.
- Standard / High / Best SRC labels map to distinct converter behavior and
  public latency estimates.
- `docs/release-validation.md` records the final release-Mac and target-hardware
  operator validation sequence.

**Known caveats (carried forward):**
- v0.5.0 has been tagged and the signed/notarized/stapled DMG has been
  published to GitHub; future public artifacts still require operator review
  before upload.
- PKG remains maintainer-only/future until Developer ID Installer validation and
  installer UX are intentionally promoted.
- Live USB-C AirPods/Cubase soak evidence remains operator-dependent hardware
  validation; automated and release-artifact gates are complete.
- Some v0.2/v0.3 operator-dependent verification items (live DAW soak, installed
  driver build-ID sync) remain deferred and are recorded in STATE.md.

## Current Milestone: v0.9 Public Polish Final Hardening

**Goal:** Close the final code, documentation, and release-automation polish gaps
before treating APM44 Bridge as public-ready.

**Target features:**
- Strictly validate ASBD Float32 stereo byte layout before IOProc code trusts
  interleaved or non-interleaved buffer memory.
- Align shared-memory build-id and sample-rate wording with the actual hard
  validation behavior, or enforce the missing compatibility checks.
- Normalize public version, latency-default, release path, and artifact wording
  across user-facing docs and maintainer docs.
- Make the one-command release path run strict codesign verification before
  notarization.
- Clarify whether `sign-notarize.yml` produces public artifacts or is only
  maintainer evidence.

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

- [x] Metrics publication is demonstrably data-race-free under standard C++ and
  ThreadSanitizer. — v0.4
- [x] Metrics JSON serialization cannot read past its fixed stack buffer when
  output is truncated. — v0.4
- [x] Core Audio virtual-device and non-interleaved callback error paths fail
  safely without null IOProc cleanup or buffer overreads. — v0.4
- [x] Release scripts and signing workflows fail closed for notarization and app
  build failures unless an explicit local-development override is set. — v0.4
- [x] Shared-memory mode `0666` has a clear public threat model and no security
  overclaiming. — v0.4
- [x] Realtime helper names/comments match actual drop-new behavior; unused
  silence helpers are deleted or corrected. — v0.4
- [x] Public distribution path documents or implements professional installer
  expectations: stapled inner artifacts, strict DMG notarization, and signed PKG
  direction. — v0.4
- [x] Release GitHub Actions near credentials/artifacts are pinned or explicitly
  tracked as a release-hardening decision. — v0.4
- [x] Public-release regression and validation gates cover all blocker fixes. — v0.4

- [x] MetricsPublisher is demonstrably data-race-free under standard C++ and ThreadSanitizer. — v0.5 (Phase 17, METR-01/METR-02)
- [x] Metrics JSON serialization cannot read past its fixed stack buffer when output is truncated. — v0.5 (Phase 17, METR-03)
- [x] Core Audio virtual-device and non-interleaved callback error paths fail safely without null IOProc cleanup or buffer overreads. — v0.5 (Phase 18, CORE-01/CORE-02)
- [x] Release scripts and signing workflows fail closed for notarization and app build failures unless an explicit local-development override is set. — v0.5 (Phase 19, REL-01/REL-02/REL-03)
- [x] Shared-memory mode `0666` has a clear public threat model and no security overclaiming. — v0.5 (Phase 20, SEC-01)
- [x] Realtime helper names/comments match actual drop-new behavior; unused silence helpers are deleted or corrected. — v0.5 (Phase 20, SEC-02/SEC-03)
- [x] Public distribution path documents or implements professional installer expectations: stapled inner artifacts, strict DMG notarization, and signed PKG direction. — v0.5 (Phase 21, DIST-01/DIST-02)
- [x] Release GitHub Actions near credentials/artifacts are pinned or explicitly tracked as a release-hardening decision. — v0.5 (Phase 21, CI-01)
- [x] Public-release regression and validation gates cover all blocker fixes. — v0.5 (Phase 22, QA-01/QA-02)

- [x] HAL mono-lane timestamp pairing rejects unrelated mismatches and preserves only explicit rollover-tolerant pairing. — v0.6 (Phase 23, HAL-01)
- [x] Mixed-output processing ignores callbacks when IO is stopped. — v0.6 (Phase 23, HAL-02)
- [x] Legacy AudioToolbox converter comparison path is removed before public release. — v0.6 (Phase 24, CONV-01)
- [x] Realtime metrics publication stores floating payloads through packed atomic integer representation. — v0.6 (Phase 24, METR-01)
- [x] Device catalog refresh cannot deadlock on unread stderr. — v0.6 (Phase 25, APP-01)
- [x] Metrics staleness state resets cleanly across start and idle transitions. — v0.6 (Phase 25, APP-02)
- [x] DMG installer app copy is deterministic and privileged. — v0.6 (Phase 25, DIST-01)
- [x] GitHub CI runs release-script regressions and guards against removal. — v0.6 (Phase 25, CI-01)
- [x] Drop-policy comments match the implemented drop-new behavior. — v0.6 (Phase 23, DOC-01)
- [x] Full v0.6 regression gate reconciles all release-safety evidence. — v0.6 (Phase 26, QA-01)
- [x] Manual signing workflow builds, embeds, signs, and verifies the same
  Release app artifact. — v0.7 (Phase 27, SIGN-01/SIGN-02/SIGN-03)
- [x] Local CI proves the app bundle under test contains the current embedded
  daemon. — v0.7 (Phase 27, CI-01/CI-02/CI-03)
- [x] Release codesign verification fails hard on missing Hardened Runtime or
  Developer ID Application identity unless explicitly overridden. — v0.7 (Phase 28, REL-01/REL-02)
- [x] Realtime metrics storage has a compile-time lock-free assertion for packed
  `std::atomic<uint64_t>` payloads. — v0.7 (Phase 28, METR-01)
- [x] Clean running-process termination transitions through the central idle
  reset path. — v0.7 (Phase 28, APP-01)
- [x] Full final release-polish verification covers v0.7 changes. — v0.7 (Phase 29, QA-01)
- [x] Manual signing workflow builds the HAL driver target before calling
  `scripts/sign-release.sh`. — v0.8 (Phase 30)
- [x] Manual signing workflow fails when required signing or notarization
  credentials are missing. — v0.8 (Phase 30)
- [x] Driver-only notarization uses the shared strict notary acceptance helper.
  — v0.8 (Phase 30)
- [x] Public release docs, SRC quality behavior, and release-candidate
  validation evidence were aligned for the v0.8 candidate. — v0.8 (Phases 31-32)

### Active

- [ ] `AsbdMatchesFloat32Stereo` rejects Float32 stereo ASBDs whose
  bytes-per-frame, bytes-per-packet, frames-per-packet, packed flag, or
  non-interleaved flag do not exactly match the IOProc memory contract.
- [ ] Shared-memory documentation accurately distinguishes hard validation gates
  from diagnostic build-id evidence, or the code enforces build-id/sample-rate
  compatibility before opening a ring.
- [ ] Public docs and templates use one release version identity, the real Safe
  fresh-install latency default, and the actual HAL driver build path
  `build/Driver/APM44Bridge.driver`.
- [ ] `scripts/release-all.sh` runs strict release codesign verification after
  signed artifacts exist and before notarization continues.
- [ ] `.github/workflows/sign-notarize.yml` is either artifact-producing or
  explicitly documented as release evidence / notary dry-run only.

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
- v0.6 is seeded from the 2026-06-13 public-release safety review covering HAL
  timestamp pairing, IO lifecycle gating, legacy converter ownership, installer
  determinism, realtime metrics atomics, stderr draining, metrics UI reset, CI
  release-script coverage, and drop-policy documentation.
- v0.7 is seeded from the 2026-06-13 final public-release polish audit covering
  manual GitHub signing artifact alignment, CI embedded-daemon proof, strict
  release codesign verification, lock-free metrics atomic guarantees, and clean
  process termination reset behavior.
- v0.8 is seeded from the 2026-06-13 release-candidate closure audit covering
  missing HAL driver builds in the manual signing workflow, fail-closed signing
  and notary credential handling, strict driver-only notarization, version/docs
  truth, legacy converter cleanup, SRC quality labels, and final release-Mac
  validation.
- v0.9 is seeded from the 2026-06-14 final public-polish audit covering strict
  ASBD byte-layout validation, shared-memory build-id/sample-rate truth, public
  version/default/path consistency, release codesign self-gating, and
  `sign-notarize.yml` artifact intent.
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
| Treat v0.3 as hardening before feature expansion | The attached risk list points to correctness issues in realtime and IPC paths | ✓ Good — closed realtime, process, metrics, and shm validation |
| Treat v0.4 as public-release blocker closure before publishing | The attached blocker review identifies correctness, release automation, and security-posture issues that should not ship silently | ✓ Good — DMG-primary path validated locally with signing, notarization, stapling, and Gatekeeper acceptance |
| Keep v0.4 DMG-primary for public distribution | The DMG install flow is already shipped and can be made honest/professional now; PKG-primary needs Developer ID Installer validation before becoming public | ✓ Good — PKG remains maintainer-only/future |
| GitHub Actions trust decision for v0.4 | Official actions remain tag-pinned with Dependabot monitoring; full-length SHA pinning becomes required before moving more signing/notarization/release publication into CI | ✓ Good — documented release-hardening decision |
| Close v0.4 release validation with live DMG proof | Local Developer ID and AC_NOTARY credentials were available, so Phase 16 could validate the real DMG-primary path instead of recording credential blockers only | ✓ Good — notarized/stapled/Gatekeeper-accepted DMG generated locally |
| Treat v0.5 as a second pass on release-readiness blockers | The provided blocker review overlaps with v0.4 but is treated as the authoritative scope for this milestone; any already-fixed items were verified and regression-gated | ✓ Good — all 16 v0.5 requirements satisfied |
| Verify v0.5 metrics and Core Audio paths without source changes | v0.4 already implemented atomic-field seqlock publication, safe JSON truncation, `inputStarted` tracking, and non-interleaved clamping | ✓ Good — verification focused on evidence and requirement tags |
| Keep v0.5 DMG-primary and accept operator-dependent publication/soak gaps | Automated release-artifact gates are complete; live hardware sign-off and GitHub upload remain operator responsibilities | ✓ Good — caveats documented before release tag |
| Treat v0.6 as a public-release safety fix pass | The post-v0.5 review identifies narrow correctness and distribution risks that should close before wider public confidence | ✓ Good — shipped public-release safety fixes |
| Treat v0.7 as final release automation polish | The latest audit says the product is close but manual signing, CI bundle proof, strict codesign checks, and small runtime guards should close before public release | ✓ Good — shipped final release automation polish |
| Treat v0.8 as release-candidate closure | The latest audit identifies the remaining release-candidate blockers in signing workflow driver coverage, fail-closed credentials, HAL driver notarization, docs truth, and final validation evidence | ✓ Good — release-candidate closure shipped |
| Treat v0.9 as final public-polish hardening | The remaining audit scope is narrow: exact Core Audio memory contracts, public truth, and release-command evidence before publication | — Pending |

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
*Last updated: 2026-06-14 after v0.9 Public Polish Final Hardening milestone start*
