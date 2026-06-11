# Project Research Summary: v0.3 Realtime Audio Hardening

**Project:** APM44 Bridge
**Domain:** macOS realtime audio bridge hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Executive Summary

v0.3 should stay narrowly focused on correctness in the realtime audio, process lifecycle, metrics, and shared-memory paths. The product stack is already appropriate: C++20 for daemon/shared low-level code, Swift 6 for the menu bar process manager, Core Audio/HAL for callbacks, POSIX shm for driver-daemon IPC, Catch2 and XCTest for regression coverage. No new dependencies are recommended.

The highest risks are not missing features; they are ownership and validation bugs that can produce rare audio glitches, undefined behavior, or false confidence from CI. The roadmap should begin with the realtime callback contract, then repair Swift stop escalation and metrics publication, then harden shm validation, and finish by closing the installed-system proof gaps from v0.2.

## Key Findings

### Recommended Stack

No stack additions. Keep the existing stack and harden in place.

**Core technologies:**
- C++20: daemon/shared realtime and IPC code.
- Apple Swift 6.3.2: menu bar lifecycle and process management.
- Core Audio/HAL: callback and virtual device integration.
- POSIX shm: existing driver-daemon audio transport.
- Catch2/XCTest: regression coverage for the relevant code paths.

### Expected Features

**Must have:**
- Strict `PlanarRingBuffer` SPSC ownership.
- Full output callback coverage for actual buffer length.
- Swift stop timeout and SIGKILL escalation that cannot hang.
- C++ data-race-free metrics publication.
- Shm open/identity validation that rejects truncated and inconsistent mappings.
- Regression coverage for every hardening fix.
- Installed-system proof for QA-03/IPC-04 or explicit hardware-blocker record.

**Should have:**
- `scripts/ci.sh` dry-run gate for `scripts/verify-installed-sync.sh`.
- Bounded corrupt-header diagnostics that are safe and operator-readable.

**Defer:**
- Signed PKG installer.
- Logic/Ableton validation expansion.
- Support bundle export.

### Architecture Approach

Keep changes within existing module boundaries. Input callbacks and virtual feed remain producer paths; output callbacks remain consumer paths. Metrics should publish through atomics or a race-free buffer pattern. Swift process waiting should use explicit waiter bookkeeping instead of a single continuation. Shm readers should validate size before trusting capacity or build-ID fields.

**Major components:**
1. `BridgeInputOverrun` / `PlanarRingBuffer` - preserve SPSC ownership.
2. `IoProcHandlers` / `BridgeEngine` - process or silence complete output callbacks.
3. `BridgeProcessManager` - deterministic stop timeout and escalation.
4. `BridgeEngine` metrics - race-free UI/control publication.
5. `MmapShmRing` / `ShmObjectIdentity` - robust mapping validation and diagnostics.
6. Verification scripts - CI dry-run plus manual live proof.

### Critical Pitfalls

1. **Keeping producer-side drop-oldest** - remove input-side `pop()` or move oldest trimming to output thread.
2. **Clamping callbacks without touching the tail** - render or silence all actual output frames.
3. **Continuation cancellation deadlock** - use explicit waiters and resume on timeout or termination.
4. **Seqlock over non-atomic payload** - replace with atomics or a genuinely race-free buffer scheme.
5. **Header-only shm validation** - compare mapped size with `ShmTotalSize(capacity_frames)` and bound build-ID formatting.
6. **CI-only sign-off** - finish with installed helper/driver/live ring evidence.

## Implications for Roadmap

### Phase 9: Realtime Callback Ownership

**Rationale:** The SPSC violation and output-tail behavior are closest to the audio callback and highest risk for glitches.
**Delivers:** Safe overrun policy, full output callback coverage, updated C++ tests.
**Addresses:** Ring ownership and large callback table stakes.
**Avoids:** Locks/allocations in IOProc and stale test assumptions.

### Phase 10: Process and Metrics Races

**Rationale:** Stop escalation and metrics publication are cross-thread correctness problems with bounded scope.
**Delivers:** Swift waiter registry, SIGKILL timeout coverage, race-free metrics publication.
**Uses:** XCTest plus Catch2/source-level C++ validation.
**Implements:** Lifecycle and control-plane hardening.

### Phase 11: Shared-Memory Validation

**Rationale:** Shm validation should be hardened before final installed proof because live verification depends on safe readers.
**Delivers:** Size checks, bounded build-ID diagnostics, corrupt/truncated shm tests.
**Implements:** IPC safety hardening.

### Phase 12: Verification Closure

**Rationale:** v0.2 accepted QA-03/IPC-04 as gaps; v0.3 should close or explicitly re-record hardware blockers after code hardening.
**Delivers:** CI dry-run installed-sync gate, full repo verification, live installed app/helper/driver/ring proof, Cubase/hotplug soak evidence where hardware is available.

### Phase Ordering Rationale

- Realtime callback ownership comes first because later metrics and live soak evidence are not trustworthy while the audio ring contract is violated.
- Swift stop and metrics fit together because both are race/coordination fixes with existing test harnesses.
- Shm validation follows because it is the remaining IPC correctness layer and feeds final live proof.
- Verification closes last so it reflects the hardened code, not the pre-v0.3 baseline.

### Research Flags

- **Phase 9:** Decide drop-newest versus output-owned drop-oldest before implementation planning.
- **Phase 9:** Decide tail silence versus chunked output; tail silence is the smallest defensive fix, chunking is more complete.
- **Phase 10:** Choose independent atomics versus double-buffer metrics during planning.
- **Phase 12:** Live proof depends on target hardware, HAL reinstall permissions, and Cubase availability.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified from local CMake, Swift, clang, tests, and scripts. |
| Features | HIGH | Directly derived from attached bug/risk list and v0.2 deferred items. |
| Architecture | HIGH | Grounded in local source paths and existing module boundaries. |
| Pitfalls | HIGH | Each pitfall maps to a named current code path or deferred verification gap. |

**Overall confidence:** HIGH

### Gaps to Address

- **Overrun policy choice:** Plan Phase 9 should explicitly choose drop-newest or output-owned drop-oldest.
- **Callback strategy:** Plan Phase 9 should choose tail silence or chunking with converter/input-demand implications.
- **Live hardware availability:** Phase 12 may need a blocker record if Cubase/AirPods/HAL reinstall cannot be run in this session.

## Sources

### Primary

- User-provided highest-priority bug/risk list.
- Local source audit: `BridgeInputOverrun.h`, `PlanarRingBuffer.cpp`, `IoProcHandlers.cpp`, `BridgeEngine.cpp`, `MmapShmRing.cpp`, `ShmObjectIdentity.h`, `BridgeProcessManager.swift`.
- Existing tests: `test_hardening_audit.cpp`, `test_mmap_shm_ring.cpp`, `test_bridge_process_manager.swift`, `tests/CMakeLists.txt`.
- Existing verification scripts: `scripts/ci.sh`, `scripts/verify-installed-sync.sh`, `scripts/verify-hal-driver.sh`.
- Current planning context: `.planning/PROJECT.md`, `.planning/STATE.md`.

---
*Research completed: 2026-06-12*
*Ready for roadmap: yes*
