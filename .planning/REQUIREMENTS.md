# Requirements: APM44 Bridge v1.0 Realtime Race Blocker Closure

**Defined:** 2026-06-14
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v1.0 Requirements

### Drift Controller Ownership

- [ ] **DRIFT-01**: `BridgeInputOverrun.h` no longer includes or names
  `DriftController`, and the input overrun helper returns an overrun flag instead
  of mutating drift state.
- [ ] **DRIFT-02**: `BridgeEngine::onInput` increments a dedicated
  `std::atomic<uint64_t>` input-overrun counter when the ring drops incoming
  frames.
- [ ] **DRIFT-03**: The output callback remains the sole owner of
  `DriftController` PI mutation, underrun notification, and drift-state reads.
- [ ] **DRIFT-04**: Metrics snapshots publish drift underruns from the
  output-owned `DriftController` and input overruns from the atomic input counter.
- [ ] **DRIFT-05**: Regression tests prove the input overrun helper returns a
  flag and cannot reintroduce `DriftController` or `notifyOverrun` into the
  producer-side callback path.

### HAL IO Lifecycle Atomicity

- [ ] **HALIO-01**: `ShmIoHandler::ioRunning_` is a `std::atomic<bool>` shared
  across HAL start, stop, and mixed-output callbacks.
- [ ] **HALIO-02**: `OnStartIO`, `OnStopIO`, and `OnProcessMixedOutput` use an
  explicit memory-ordering contract for the stopped-IO guard.
- [ ] **HALIO-03**: Regression tests or source-audit guards fail if
  `ioRunning_` returns to a plain `bool`.
- [ ] **HALIO-04**: Existing stopped-IO behavior remains intact: mixed-output
  callbacks do not push frames when IO is not running.

### Mono-Lane Callback Serialization

- [ ] **MONO-01**: The mono-lane pending queue has a source comment citing the
  libASPL/Core Audio callback serialization contract, or the queue is redesigned
  so concurrent per-stream callbacks cannot race on shared lane state.
- [ ] **MONO-02**: Tests exercise the expected serialized mono-lane callback
  pattern, including compatible lane pairing and old unmatched lane drops.
- [ ] **MONO-03**: A source-audit guard fails if shared mono-lane callback state
  exists without an explicit serialization contract or thread-safe redesign.
- [ ] **MONO-04**: The existing timestamp/logical-sample mismatch protections
  remain covered after the serialization proof or redesign.

### Verification Closure

- [ ] **QA-01**: Source-audit tests cover the named blocker contracts:
  `BridgeInputOverrunDoesNotIncludeDriftController`,
  `BridgeInputOverrunReturnsOverrunFlagInsteadOfMutatingDrift`,
  `BridgeEngineInputOverrunCounterIsAtomic`,
  `ShmIoHandlerIoRunningIsAtomic`, and
  `ShmIoHandlerMonoLaneCallbackSerializationDocumented`.
- [ ] **QA-02**: Full repo CI (`scripts/ci.sh`) passes after the realtime race
  blocker fixes.
- [ ] **QA-03**: Installed app/helper/driver synchronization checks remain
  green through the repo's trusted verification entrypoints.
- [ ] **QA-04**: Release validation records final operator-owned Cubase 15 and
  USB-C AirPods Max smoke/soak status without overclaiming unavailable hardware
  evidence.

## Future Requirements

### Compatibility

- **COMP-01**: Validate Logic and Ableton host behavior after the Cubase 15
  USB-C AirPods path remains stable.

### Distribution

- **PKG-01**: Promote signed PKG installer validation from maintainer-only to a
  public release path after Developer ID Installer validation is intentionally
  completed.
- **PUB-01**: Automate GitHub release upload/publication after the maintainer is
  ready to move artifact publication out of the operator-owned path.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New DSP/resampler architecture | v1.0 is a realtime race blocker closure, not an audio-engine rewrite. |
| Broad DAW validation matrix | Cubase 15 USB-C AirPods remains the public validation anchor for this release. |
| PKG-primary public installer | Remains future/maintainer-only until Developer ID Installer validation is completed. |
| Replacing libASPL wholesale | Only the callback serialization contract needs proof or containment for this milestone. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DRIFT-01 | Phase 38 | Pending |
| DRIFT-02 | Phase 38 | Pending |
| DRIFT-03 | Phase 38 | Pending |
| DRIFT-04 | Phase 38 | Pending |
| DRIFT-05 | Phase 38 | Pending |
| HALIO-01 | Phase 39 | Pending |
| HALIO-02 | Phase 39 | Pending |
| HALIO-03 | Phase 39 | Pending |
| HALIO-04 | Phase 39 | Pending |
| MONO-01 | Phase 40 | Pending |
| MONO-02 | Phase 40 | Pending |
| MONO-03 | Phase 40 | Pending |
| MONO-04 | Phase 40 | Pending |
| QA-01 | Phase 41 | Pending |
| QA-02 | Phase 41 | Pending |
| QA-03 | Phase 41 | Pending |
| QA-04 | Phase 41 | Pending |

**Coverage:**
- v1.0 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-06-14*
*Last updated: 2026-06-14 after v1.0 roadmap creation*
