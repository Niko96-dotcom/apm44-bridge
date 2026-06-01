# Phase 4: HAL Virtual Device - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning
**Mode:** Smart discuss (yolo)

<domain>
## Phase Boundary

Ship `APM44Bridge.driver` HAL Audio Server Plug-in exposing **APM44 Bridge** @ 44100 Hz 2ch Float32. Driver copies DAW buffers to shared-memory SPSC ring; user-space `apm44-bridge` consumes ring and continues SRC to AirPods. Driver must NOT open AirPods or run SRC. Document install to `/Library/Audio/Plug-Ins/HAL/`. DAW can use APM44 Bridge without BlackHole.

</domain>

<decisions>
## Implementation Decisions

### Driver stack
- Use **libASPL** (git submodule, pinned SHA) for C++17 HAL plug-in
- Device UID `com.niko.apm44.bridge.device`; name **APM44 Bridge**
- Advertise **44100 Hz only** in nominal rates
- `DoIOOperation` RT path: memcpy to/from shared ring only — no alloc/locks

### IPC
- POSIX `shm_open` + mmap ring in `Shared/` (same layout as research ARCHITECTURE.md)
- Control channel: optional XPC later; Phase 4 uses file lock + atomic write index in shm header
- Daemon mode `--virtual-device` reads from ring instead of BlackHole HAL input

### Packaging
- `Driver/APM44Bridge.driver` bundle; `scripts/install-driver.sh` (sudo) for dev
- README section: Developer ID signing deferred to Phase 5 but entitlements documented

### Claude's Discretion
- libASPL version pin
- Exact ring header struct layout

</decisions>

<code_context>
## Existing Code Insights

- Phase 1-3 daemon and menu bar
- `Shared/PlanarRingBuffer` — extend for cross-process mmap

</code_context>

<specifics>
DRV-01, DRV-02, DRV-03, DEV-01, DEV-02, DEV-03

</specifics>

<deferred>
Notarization matrix (Phase 5)

</deferred>
