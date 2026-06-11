# Architecture Research: v0.3 Realtime Audio Hardening

**Domain:** macOS realtime audio bridge hardening
**Researched:** 2026-06-12
**Confidence:** HIGH for local architecture, MEDIUM for final phase split

## Standard Architecture

### System Overview

```text
Cubase / DAW @ 44.1 kHz
        |
        v
APM44 HAL virtual output in coreaudiod
        |
        v
POSIX shm ring `/apm44_bridge_ring`
        |
        v
Bridge daemon
  - virtual feed drains shm
  - planar ring buffers input-rate audio
  - SRC converts 44.1 -> 48 kHz
  - output IOProc writes monitoring device
        |
        v
USB-C AirPods Max @ 48 kHz

Menu bar app
  - launches/stops daemon
  - watches devices/hotplug
  - parses metrics
  - guides live verification
```

### Component Responsibilities

| Component | Responsibility | Current Risk |
|-----------|----------------|--------------|
| `PlanarRingBuffer` | Lock-free SPSC planar audio storage | Contract says SPSC, but producer path can also pop. |
| `BridgeInputOverrun` | Overrun policy when input cannot push full callback | Current drop-oldest policy mutates consumer index from producer thread. |
| `IoProcHandlers` | Convert Core Audio buffers to engine callbacks | Current clamp can leave unprocessed output tail. |
| `BridgeEngine` metrics | Publish fill/ratio/xrun counters to control loop | Current seqlock copies a non-atomic payload across threads. |
| `BridgeProcessManager` | App process lifecycle and restart/stop escalation | Current timeout path can hang if continuation child is cancelled. |
| `MmapShmRing` / `ShmObjectIdentity` | Map and validate HAL shared-memory ring | Current validation omits total-size checks and bounded build-ID formatting. |
| `scripts/ci.sh` | Non-hardware gate | Does not yet gate `verify-installed-sync.sh --dry-run`. |

## Recommended Project Structure

Keep changes inside existing ownership boundaries:

```text
BridgeDaemon/src/engine/
  BridgeInputOverrun.h       # Replace or retire producer-side drop-oldest policy
  IoProcHandlers.cpp         # Full callback coverage and tail silence/chunking
  BridgeEngine.{h,cpp}       # Race-free metrics publication

Shared/include/apm44/
  PlanarRingBuffer.h         # Clarify SPSC contract if needed
  ShmRingLayout.h            # Size validation helpers and bounded build-ID utilities
  ShmObjectIdentity.h        # Header-size guard before mmap/read generation

Shared/src/
  MmapShmRing.cpp            # Mapping size validation and safe diagnostics

App/APM44Bridge/
  BridgeProcessManager.swift # Explicit termination waiter bookkeeping

tests/
  test_hardening_audit.cpp
  test_mmap_shm_ring.cpp
  test_shm_object_identity.cpp
  test_bridge_process_manager.swift
```

## Architectural Patterns

### Pattern 1: Preserve Callback Ownership

**What:** Each IOProc owns only the operations assigned by the lock-free contract.
Input may push, output may pop; no side owns both indices unless the buffer is redesigned.

**When to use:** `PlanarRingBuffer` overrun handling.

**Trade-offs:** Drop-newest may lose incoming frames; output-owned drop-oldest is more complex. Both are safer than cross-thread consumer-index mutation.

### Pattern 2: Whole-Buffer Output Guarantees

**What:** Treat Core Audio's actual buffer length as the output contract. If the engine can only process a chunk, explicitly silence or process subsequent chunks.

**When to use:** `OutputIoProc()` for interleaved and non-interleaved output.

**Trade-offs:** Tail silence is simpler and safe; chunking is more complete but can disturb input-demand accounting and converter continuity if done casually.

### Pattern 3: Race-Free Metrics by Construction

**What:** Publish metrics via independent atomics or a double-buffer scheme where readers never observe a buffer being written.

**When to use:** `BridgeEngine::publishMetricsSnapshot()` and `readMetricsSnapshot()`.

**Trade-offs:** Independent atomics may produce slightly inconsistent snapshots, but that is acceptable for UI metrics and avoids undefined behavior.

### Pattern 4: Explicit Swift Waiter Registry

**What:** Store termination waiters as individual entries; timeout removes/resumes its own waiter, termination resumes all pending waiters.

**When to use:** `BridgeProcessManager.waitForTermination()`.

**Trade-offs:** Slightly more bookkeeping, but deterministic timeout and supports concurrent waits.

### Pattern 5: Validate Before Trust

**What:** Validate shm object size before mapping header reads and before trusting `capacity_frames`.

**When to use:** `MmapShmRing::open()`, `ReadLiveDriverGeneration()`, and header mismatch reporting.

**Trade-offs:** More explicit failure paths, but safer diagnostics and no out-of-bounds access on malformed objects.

## Data Flow

### Realtime Audio Flow

```text
Input callback / virtual feed
    -> push only
    -> PlanarRingBuffer write index

Output callback
    -> optional output-owned trim/rebuffer policy
    -> pop only
    -> SRC
    -> full Core Audio output buffer
```

### Metrics Flow

```text
Output callback
    -> publish atomic metric fields
Control loop / CLI JSON
    -> read latest atomics
Menu bar app
    -> parse stdout JSON
    -> display metrics/staleness
```

### Stop/Restart Flow

```text
User/settings/hotplug action
    -> initiateStop(reason)
    -> waitForTermination(timeout)
    -> terminate, then SIGKILL on timeout
    -> handleTermination resumes waiters
    -> restart or idle/error transition
```

### Shared-Memory Validation Flow

```text
shm_open
    -> fstat size >= sizeof(ShmRingHeader)
    -> mmap header or full object
    -> validate magic/version/header/channels/capacity
    -> validate mapped size >= ShmTotalSize(capacity)
    -> capture identity/generation
    -> only then push/pop
```

## Anti-Patterns

### Anti-Pattern 1: Fixing Real-Time Races with Locks

**What people do:** Add a mutex around ring operations.
**Why it's wrong:** Locks in IO callbacks can block the audio device.
**Do this instead:** Preserve single-owner operations and use atomics for scalar cross-thread publication.

### Anti-Pattern 2: Treating Tests as the Spec When Tests Encode a Bug

**What people do:** Keep `test_hardening_audit.cpp` expecting producer-side drop-oldest.
**Why it's wrong:** That test verifies a behavior that violates the SPSC contract.
**Do this instead:** Rewrite the test around the new ownership policy.

### Anti-Pattern 3: Header Validation Without Size Validation

**What people do:** Accept a valid-looking header from a tiny shm object.
**Why it's wrong:** Ring operations then index beyond the mapped object.
**Do this instead:** Validate `st_size` against `ShmTotalSize(capacity_frames)`.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Input IOProc -> `PlanarRingBuffer` | Push-only SPSC producer | Do not call `pop()` from input path. |
| Output IOProc -> `PlanarRingBuffer` | Pop-only SPSC consumer | Any oldest-drop policy belongs here if retained. |
| Output IOProc -> metrics | Atomic publication | Avoid non-atomic shared struct payload. |
| App -> daemon process | `Process`, pipes, termination handler | Explicit waiters must survive timeout/cancellation paths. |
| HAL driver -> daemon | POSIX shm | Validate size/header/build IDs before trusting payload layout. |
| CI -> installed sync | shell script dry-run | Add non-hardware check to `scripts/ci.sh`; keep live check manual. |

## Sources

- Local source audit of the files listed in Recommended Project Structure.
- Existing v0.2 research and current `.planning/PROJECT.md` state.
- Existing test inventory from `tests/CMakeLists.txt` and Swift app tests.

---
*Architecture research for: v0.3 Realtime Audio Hardening*
*Researched: 2026-06-12*
