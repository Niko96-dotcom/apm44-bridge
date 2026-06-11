# Feature Research: v0.3 Realtime Audio Hardening

**Domain:** realtime audio bridge correctness and verification
**Researched:** 2026-06-12
**Confidence:** HIGH

## Feature Landscape

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Strict SPSC ring ownership | A lock-free SPSC buffer is only safe when one thread owns writes and one owns reads. | MEDIUM | `DropOldestThenPush()` currently calls `ring.pop()` from input callback; output callback also pops. |
| Full output callback coverage | Core Audio expects the callback to produce valid audio for the buffer it receives. | MEDIUM | Current clamp to 1024 frames can leave output tails untouched. |
| Timeout-safe process stop | User Stop, Restart, settings changes, and hotplug recovery must not hang. | MEDIUM | Current task-group continuation can be cancelled without resuming. |
| Race-free metrics publication | UI and logs should not read non-atomic fields while the IO thread writes them. | MEDIUM | Current seqlock protects intent but not the C++ memory model. |
| Defensive shm validation | Daemon must reject malformed or stale shm before trusting ring capacity. | MEDIUM | Current open validates header fields but not mapped size versus declared capacity. |
| Regression coverage for each hardening path | These are low-level correctness fixes; tests must prevent reintroduction. | MEDIUM | Existing hardening audit should be updated rather than expanded around stale assumptions. |
| Installed-system proof | The bridge is only fixed when repo daemon, app helper, driver, and live ring agree. | HIGH | QA-03 and IPC-04 were deferred from v0.2 and should close in this milestone. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Deterministic overrun policy | Makes audio behavior explainable under overload instead of timing-dependent. | MEDIUM | Choose either drop-newest on input or output-owned drop-oldest. |
| Callback chunking | Allows large buffers without resizing scratch to every possible device size. | HIGH | More complete than tail silence; requires careful input-demand/converter handling. |
| Dry-run installed-sync CI gate | Catches helper/repo build-ID drift before manual live verification. | LOW | `verify-installed-sync.sh --dry-run` can be added to `scripts/ci.sh` without requiring a running bridge. |
| Bounded corrupt-header diagnostics | Makes IPC failures actionable without unsafe reads. | LOW | Replace raw C-string output with bounded formatting. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Dynamically allocate larger scratch buffers inside IOProc | Simple fix for >1024 frame callbacks. | Allocation in real-time callback path is unsafe. | Preallocate larger buffers during prepare or process in bounded chunks. |
| Lock around ring operations | Appears to fix index races. | Blocking in IOProc can cause audio glitches and deadlocks. | Preserve SPSC ownership and use atomics only for cross-thread metrics. |
| Treat metrics consistency as not important | Metrics are UI-only, so races look harmless. | Undefined behavior can still corrupt reads or hide faults. | Independent atomics or race-free double-buffer publication. |
| Force live verification into CI | Would prove more. | CI lacks target hardware, HAL install, and AirPods visibility. | CI-gate dry-run/static sync; keep live checklist manual. |

## Feature Dependencies

```text
Ring ownership
    -> Metrics atomics are easier once overrun counters have clear ownership
    -> Output callback behavior depends on output-side consumer ownership

Output callback coverage
    -> Requires explicit policy for oversized callbacks
    -> Should run before final live soak

Swift stop waiters
    -> Required before trusting hotplug/settings restart soak

Shm validation
    -> Required before final installed-system proof

CI/live proof
    -> Depends on code fixes and regression coverage
```

### Dependency Notes

- **Ring ownership before metrics:** `DriftController::notifyOverrun()` mutates a plain counter from the input thread while output/control paths can read metrics. Clarify ownership or atomize counters before treating metrics as safe.
- **Callback coverage before soak:** The live Cubase soak is only meaningful after callback tail behavior is deterministic.
- **Swift stop before recovery proof:** Hotplug/settings recovery depends on stop/restart finishing under timeout and escalation.
- **Shm validation before live sync proof:** Installed sync should not rely on shm readers that can trust corrupt sizes.

## MVP Definition

### Launch With (v0.3)

- [ ] Strict SPSC ring overrun policy with updated tests.
- [ ] Output callback path fills or silences every provided frame.
- [ ] Swift termination wait cannot hang and supports multiple waiters.
- [ ] Metrics publication is C++ race-free.
- [ ] Shm open/identity diagnostics reject truncated/corrupt mappings safely.
- [ ] CI covers hardening regressions and dry-run installed-sync.
- [ ] Manual QA-03/IPC-04 checklist is completed or explicitly recorded with hardware caveat.

### Add After Validation

- [ ] More DAW validation beyond Cubase - defer until realtime correctness is quiet.
- [ ] Support bundle export - useful, but not required to fix the low-level risks.

### Future Consideration

- [ ] Signed PKG installer - packaging milestone, not realtime hardening.
- [ ] Logic/Ableton matrix - compatibility milestone after v0.3.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| SPSC ring ownership | HIGH | MEDIUM | P1 |
| Output callback coverage | HIGH | MEDIUM | P1 |
| Swift stop waiters/escalation | HIGH | MEDIUM | P1 |
| Metrics race-free publication | MEDIUM | MEDIUM | P1 |
| Shm validation hardening | HIGH | MEDIUM | P1 |
| CI dry-run installed-sync | MEDIUM | LOW | P2 |
| Live QA-03/IPC-04 proof | HIGH | HIGH | P1 |
| Support bundle export | MEDIUM | MEDIUM | P3 |
| PKG signing | MEDIUM | HIGH | P3 |

## Sources

- User-provided highest-priority bug/risk list attached to `$gsd-new-milestone`.
- Local source audit: `BridgeInputOverrun.h`, `IoProcHandlers.cpp`, `BridgeProcessManager.swift`, `BridgeEngine.cpp`, `MmapShmRing.cpp`, `ShmObjectIdentity.h`.
- Existing tests: `tests/test_hardening_audit.cpp`, `tests/test_mmap_shm_ring.cpp`, `tests/test_bridge_process_manager.swift`.
- v0.2 planning context: `.planning/PROJECT.md`, `.planning/STATE.md`.

---
*Feature research for: v0.3 Realtime Audio Hardening*
*Researched: 2026-06-12*
