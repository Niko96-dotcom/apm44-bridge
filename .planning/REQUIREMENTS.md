# Requirements: APM44 Bridge

**Defined:** 2026-06-11
**Milestone:** v0.2 Reliability and Self-Healing
**Core Value:** A producer can start monitoring once and trust Cubase at 44.1
kHz to keep playing through USB-C AirPods at 48 kHz without silent wedges or
mystery relaunches.

## v0.2 Requirements

### App Lifecycle

- [x] **APP-01**: User can click Start after any error and the bridge attempts a
  fresh launch instead of silently doing nothing.
- [x] **APP-02**: User-initiated Stop is tracked separately from unexpected
  daemon exits, so only unexpected/recoverable failures trigger auto-recovery.
- [x] **APP-03**: User can explicitly restart the bridge from the menu, including
  from running or error states.
- [x] **APP-04**: User sees accurate Start/Stop/Restart availability that matches
  the manager state.
- [x] **APP-05**: User sees reconnecting, retry, and final error messages that
  explain what the bridge is doing and include actionable failure text.

### Restart and Device Recovery

- [x] **REC-01**: User can change latency, SRC quality, or output device while
  running and the bridge restarts only after the previous daemon has actually
  terminated.
- [x] **REC-02**: User gets bounded automatic retry with backoff after an
  unexpected daemon exit.
- [x] **REC-03**: User gets hotplug recovery even when the menu window is closed.
- [x] **REC-04**: User can disconnect and reconnect the selected USB-C AirPods and
  the bridge reconnects without requiring a DAW restart when the device returns.
- [x] **REC-05**: User cannot select APM44 Bridge, BlackHole, or other virtual
  loopback devices as the physical monitoring output.

### HAL IPC Self-Healing

- [ ] **IPC-01**: Daemon detects that the named HAL shared-memory object has been
  recreated while it is still mapped to an old object.
- [ ] **IPC-02**: Daemon handles stale shared-memory identity by remapping on a
  non-real-time path or exiting with a distinct recoverable status and stderr
  message.
- [ ] **IPC-03**: App classifies the daemon's stale-ring recovery signal as
  recoverable and relaunches within the bounded retry policy.
- [ ] **IPC-04**: Verification proves that the repo build, installed HAL driver,
  installed app helper, and live shm ring build IDs all match.

### Audio and Process Hardening

- [x] **AUD-01**: CLI runs without `--metrics-json` without busy-spinning a CPU
  core.
- [x] **AUD-02**: IOProc handlers clamp callback frame counts to scratch capacity
  and avoid buffer overflow on oversized device callbacks.
- [x] **AUD-03**: Input overrun handling preserves the single-producer,
  single-consumer contract of the planar ring.
- [x] **AUD-04**: Shared-memory ring methods check mapping/header state before
  dereferencing header data.
- [x] **AUD-05**: Metrics written from audio/control threads are synchronized
  before being read by the metrics tick.
- [x] **AUD-06**: Process shutdown clears stdout and stderr handlers and escalates
  if a daemon does not terminate after a stop request.
- [x] **AUD-07**: Latency controls and labels reflect the real HAL-mode target
  fill behavior, including any minimum clamp.

### Verification

- [x] **QA-01**: Automated Swift tests cover manager transitions from idle,
  starting, running, stopping, error, reconnecting, and retry-exhausted states.
- [x] **QA-02**: Automated C++ tests cover stale shm detection, CLI non-busy idle,
  oversize callback clamping, SPSC overrun behavior, and null-header safety.
- [ ] **QA-03**: Live verification covers `scripts/verify-hal-driver.sh`,
  `apm44-bridge --shm-status`, installed app/helper synchronization, hotplug
  recovery, and a Cubase HAL smoke/soak.

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
| LaunchAgent auto-start | Open at login is the current app-owned path; reliability must work before daemonization. |
| Bluetooth-only AirPods mode | USB-C AirPods Max is the low-jitter product target. |
| New DSP/resampler architecture | Audit found lifecycle bugs, not a broken DSP core. |
| Publishing `.planning/` | The public repo intentionally ignores internal planning artifacts. |
| Broad DAW matrix expansion | Cubase 15 HAL path remains the milestone validation anchor. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| APP-01 | Phase 5 | Complete |
| APP-02 | Phase 5 | Complete |
| APP-03 | Phase 5 | Complete |
| APP-04 | Phase 5 | Complete |
| APP-05 | Phase 5 | Complete |
| REC-01 | Phase 5 | Complete |
| REC-02 | Phase 6 | Complete |
| REC-03 | Phase 6 | Complete |
| REC-04 | Phase 6 | Complete |
| REC-05 | Phase 6 | Complete |
| IPC-01 | Phase 7 | Pending |
| IPC-02 | Phase 7 | Pending |
| IPC-03 | Phase 7 | Pending |
| IPC-04 | Phase 7 | Pending |
| AUD-01 | Phase 8 | Complete |
| AUD-02 | Phase 8 | Complete |
| AUD-03 | Phase 8 | Complete |
| AUD-04 | Phase 8 | Complete |
| AUD-05 | Phase 8 | Complete |
| AUD-06 | Phase 8 | Complete |
| AUD-07 | Phase 8 | Complete |
| QA-01 | Phase 5 | Complete |
| QA-02 | Phase 8 | Complete |
| QA-03 | Phase 8 | Pending |

**Coverage:**
- v0.2 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0

---
*Requirements defined: 2026-06-11*
*Last updated: 2026-06-11 after milestone v0.2 definition*
