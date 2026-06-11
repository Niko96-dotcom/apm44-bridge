# Requirements: APM44 Bridge

**Defined:** 2026-06-12
**Milestone:** v0.3 Realtime Audio Hardening
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v0.3 Requirements

### Realtime Callback Safety

- [ ] **RT-01**: Input overrun handling preserves the `PlanarRingBuffer`
  single-producer / single-consumer contract; the input producer path never
  consumes from the ring.
- [ ] **RT-02**: The selected overrun policy is explicit, tested, and explains
  whether new input is dropped or oldest-frame trimming is performed by the
  output consumer.
- [ ] **RT-03**: Output callbacks larger than the internal scratch capacity
  render or explicitly silence every frame Core Audio provides.
- [ ] **RT-04**: Interleaved and non-interleaved output paths both handle
  oversized callbacks without stale tail samples or incorrect byte counts.
- [ ] **RT-05**: C++ regression tests cover the new overrun policy and oversized
  callback behavior without relying on production shared-memory names.

### Process Lifecycle Safety

- [ ] **PROC-01**: Stop and restart waits cannot hang when the daemon ignores
  termination and the timeout path fires.
- [ ] **PROC-02**: Stop escalation reliably sends SIGKILL after the graceful
  termination timeout when the daemon is still running.
- [ ] **PROC-03**: Concurrent termination waiters are tracked independently and
  all complete without overwriting each other.
- [ ] **PROC-04**: Swift lifecycle tests cover timeout, escalation, concurrent
  waiter, settings restart, and hotplug restart paths.

### Metrics Race Hardening

- [ ] **METR-01**: Metrics published from realtime/control paths are read through
  a C++ data-race-free mechanism.
- [ ] **METR-02**: Underrun, overrun, xrun, fill, ratio, and ppm metrics remain
  available to CLI JSON and app UI after the publication mechanism changes.
- [ ] **METR-03**: Metrics tests or source-level assertions prove the code no
  longer copies a plain cross-thread `MetricsSnapshot` payload.

### Shared-Memory Validation

- [ ] **SHM-01**: `MmapShmRing::open()` rejects shm objects smaller than a full
  `ShmRingHeader` before reading header fields.
- [ ] **SHM-02**: `MmapShmRing::open()` rejects valid-looking headers whose
  mapped object is smaller than `ShmTotalSize(capacity_frames)`.
- [ ] **SHM-03**: Live driver generation reads check object size before mapping
  or reading a header.
- [ ] **SHM-04**: Header mismatch diagnostics render build IDs with bounded
  string handling and never assume null termination.
- [ ] **SHM-05**: Corrupt, truncated, and inconsistent shm objects are covered by
  isolated Catch2 tests that do not touch `/apm44_bridge_ring`.

### Verification Closure

- [ ] **QA-01**: `scripts/ci.sh` runs the normal non-hardware gate and includes a
  dry-run installed-sync check for `scripts/verify-installed-sync.sh`.
- [ ] **QA-02**: Final automated verification includes CMake/Catch2 tests, Swift
  app tests, and the installed-sync dry-run gate.
- [ ] **QA-03**: Live verification proves repo daemon, embedded app helper,
  installed HAL driver, and live shm ring build IDs agree, or records the exact
  hardware/permission blocker.
- [ ] **QA-04**: Live operator verification covers `scripts/verify-hal-driver.sh`,
  `apm44-bridge --shm-status`, USB-C AirPods hotplug smoke, and Cubase HAL
  smoke/soak where hardware is available.
- [ ] **QA-05**: Milestone close updates planning state with any remaining
  hardware-only caveats instead of silently treating CI-only proof as complete.

## Future Requirements

### Packaging

- **PKG-01**: Maintainer can ship a signed PKG installer once installer signing is
  fully validated.
- **PKG-02**: End user can install without a Terminal command from the DMG.

### Broader Compatibility

- **DAW-01**: Producer can run the same reliability checks against Logic and
  Ableton with documented DAW-specific setup.
- **OUT-01**: User can choose other 48 kHz USB outputs with the same recovery
  guarantees as USB-C AirPods Max.

### Observability

- **OBS-01**: User can export a compact support bundle with app state, helper
  version, driver version, recent stderr, and shm status.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Signed PKG installer | Packaging is intentionally deferred until realtime and IPC correctness risks are closed. |
| Logic/Ableton validation matrix | Cubase 15 HAL path remains the validation anchor for this hardening milestone. |
| Support bundle export | Useful for future diagnostics, but not needed to close the attached high-priority correctness risks. |
| Bluetooth-only AirPods mode | USB-C AirPods Max remains the low-jitter product target. |
| New DSP/resampler architecture | The milestone fixes ownership, validation, and lifecycle bugs in the existing shipped path. |
| Publishing `.planning/` publicly | The public repo intentionally ignores internal planning artifacts unless explicitly force-added for local GSD state. |

## Traceability

Traceability is filled during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RT-01 | TBD | Pending |
| RT-02 | TBD | Pending |
| RT-03 | TBD | Pending |
| RT-04 | TBD | Pending |
| RT-05 | TBD | Pending |
| PROC-01 | TBD | Pending |
| PROC-02 | TBD | Pending |
| PROC-03 | TBD | Pending |
| PROC-04 | TBD | Pending |
| METR-01 | TBD | Pending |
| METR-02 | TBD | Pending |
| METR-03 | TBD | Pending |
| SHM-01 | TBD | Pending |
| SHM-02 | TBD | Pending |
| SHM-03 | TBD | Pending |
| SHM-04 | TBD | Pending |
| SHM-05 | TBD | Pending |
| QA-01 | TBD | Pending |
| QA-02 | TBD | Pending |
| QA-03 | TBD | Pending |
| QA-04 | TBD | Pending |
| QA-05 | TBD | Pending |

**Coverage:**
- v0.3 requirements: 22 total
- Mapped to phases: 0
- Unmapped: 22

---
*Requirements defined: 2026-06-12*
*Last updated: 2026-06-12 after v0.3 requirements definition*
