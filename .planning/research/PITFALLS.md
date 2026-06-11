# Pitfalls Research: v0.3 Realtime Audio Hardening

**Domain:** realtime audio, process lifecycle, and shm IPC hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Violating SPSC Ownership While Preserving the Test

**What goes wrong:**
The input callback calls `ring.pop()` to drop old frames while the output callback also pops. This can lose read-index updates or make glitches timing-dependent.

**Why it happens:**
The producer-side drop-oldest helper is convenient and has an existing test that makes the behavior look intentional.

**How to avoid:**
Choose an overrun policy that keeps input as producer only: drop-newest on input overflow, or move oldest trimming to the output side. Rewrite `test_hardening_audit.cpp` to assert the new policy.

**Warning signs:**
Any input-side code calls `PlanarRingBuffer::pop()` or mutates consumer-side state.

**Phase to address:**
First phase of v0.3.

---

### Pitfall 2: Fixing Large Callbacks by Clamping Only

**What goes wrong:**
The first 1024 frames are processed and the tail of a larger output buffer remains stale or uninitialized.

**Why it happens:**
Scratch buffers are fixed at `kMaxCallbackFrames`, and clamping is easy.

**How to avoid:**
Use the actual callback frame count as the contract. Either explicitly silence the tail after the processed chunk or process output in bounded chunks.

**Warning signs:**
`OutputIoProc()` computes `actualFrames`, clamps to `frames`, and returns without touching `[frames, actualFrames)`.

**Phase to address:**
First or second phase of v0.3.

---

### Pitfall 3: Swift Continuation Cancellation Deadlock

**What goes wrong:**
A timeout child throws, the task group cancels the continuation child, but the checked continuation never resumes. SIGKILL escalation may never run or finish.

**Why it happens:**
`withCheckedContinuation` is not automatically resumed by task cancellation, and only one stored continuation can be overwritten by concurrent waits.

**How to avoid:**
Implement explicit waiter bookkeeping. Each waiter should be resumed exactly once on termination or timeout; `handleTermination()` should resume all pending waiters.

**Warning signs:**
A test can start a stop/restart path and never observe SIGKILL or final failure when termination does not arrive.

**Phase to address:**
Second phase of v0.3.

---

### Pitfall 4: Logical Seqlock That Is Still a C++ Data Race

**What goes wrong:**
Readers copy `MetricsSnapshot` while the output callback writes its non-atomic fields. The sequence counter may make the algorithm look coherent, but the payload access remains undefined behavior.

**Why it happens:**
Seqlock examples often omit that payload races still need atomics or a carefully designed data-race-free buffer scheme in standard C++.

**How to avoid:**
Publish independent atomic fields for metrics, or implement a real double-buffer pattern where readers never touch the buffer currently being written.

**Warning signs:**
Plain `MetricsSnapshot metricsSnapshot_` is written by one thread and copied by another.

**Phase to address:**
Second or third phase of v0.3.

---

### Pitfall 5: Trusting Corrupt Shm Headers Too Early

**What goes wrong:**
A small shm object claims a large capacity; push/pop trusts `capacity_frames` and reads or writes beyond the mapped object. Diagnostics can also read beyond `producer_build_id`.

**Why it happens:**
Header fields are validated before total mapped size and bounded string handling are enforced.

**How to avoid:**
Check `fstat` size before mapping/reading headers, validate `mappedSize >= ShmTotalSize(capacity)`, and format build IDs with bounded string conversion.

**Warning signs:**
`MmapShmRing::open()` accepts a header without comparing `st_size` to `ShmTotalSize()`, or `ReadLiveDriverGeneration()` mmaps a header without checking `st_size`.

**Phase to address:**
Third phase of v0.3.

---

### Pitfall 6: Declaring the Milestone Done Without Live Proof

**What goes wrong:**
CI passes but the installed app helper, driver bundle, or live shm ring is stale.

**Why it happens:**
Hardware and sudo reinstall steps are easy to defer, and `.planning/` already records QA-03/IPC-04 as accepted gaps.

**How to avoid:**
CI-gate the dry-run installed-sync script, then perform the live `verify-hal-driver.sh` / `--shm-status` / Cubase soak checklist before closing or explicitly record hardware blockers.

**Warning signs:**
Only `scripts/ci.sh` is run before milestone close; no installed helper/driver build-ID evidence is captured.

**Phase to address:**
Final phase of v0.3.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Preserve producer-side drop-oldest | Minimal code churn | Undefined SPSC behavior remains | Never for v0.3 |
| Silence callback tail only | Fast defensive fix | Large callbacks may still under-render audio | Acceptable if documented and tested; chunking can follow if needed |
| Independent metric atomics | Simple race-free path | Snapshots may mix adjacent callback values | Acceptable for UI metrics |
| Dry-run only installed sync in CI | No hardware needed | Does not prove live ring | Acceptable as CI layer, not final sign-off |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `BridgeInputOverrun` with tests | Update implementation but leave old test expectations | Rewrite tests to encode the selected ownership policy. |
| `IoProcHandlers` interleaved output | Zero tail with wrong byte count | Account for channel count and interleaved/non-interleaved layouts. |
| Swift process tests | Use real long sleeps | Use mock launcher hooks and short deterministic timeouts/test seams. |
| Shm tests | Use production `/apm44_bridge_ring` | Continue using isolated short per-process shm names. |
| Live verification | Rebuild driver but not app helper | Verify repo daemon, embedded helper, and live shm-status build IDs match. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Locks/allocations in IOProc | Clicks, dropouts, deadlock | Preallocate, use bounded loops, avoid blocking | Under callback pressure |
| Oversized callback tail untouched | Stale audio or random output beyond first chunk | Tail silence or chunk processing | Devices with >1024 frame buffers |
| Metrics publication with UB | Rare nonsense UI values or sanitizer findings | Atomics/double buffer | Under concurrent callback/control reads |
| Shm capacity mismatch | Crash or memory corruption | Validate mapped size | Malformed/stale shm object |

## "Looks Done But Isn't" Checklist

- [ ] **Ring fix:** No input-side path can call `PlanarRingBuffer::pop()`; tests assert this behavior.
- [ ] **Callback fix:** Tests cover output buffers larger than `kMaxCallbackFrames` for interleaved and non-interleaved layouts.
- [ ] **Stop fix:** Tests prove timeout reaches escalation and concurrent waiters complete without overwriting each other.
- [ ] **Metrics fix:** `MetricsSnapshot` is not shared as a plain cross-thread payload.
- [ ] **Shm fix:** Tests cover tiny/truncated shm object, header-size object, huge claimed capacity, and unterminated build ID.
- [ ] **CI/live proof:** `scripts/ci.sh` includes non-hardware installed-sync dry-run, and final close records live installed evidence or explicit hardware blocker.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Ring ownership regression | MEDIUM | Revert helper usage, restore push-only input path, rerun ring and soak tests. |
| Output tail bug | LOW/MEDIUM | Add tail silence immediately, then evaluate chunking if audio behavior needs it. |
| Stop wait deadlock | MEDIUM | Replace continuation singleton with waiter registry, add timeout tests. |
| Metrics data race | MEDIUM | Convert fields to atomics or double-buffer; rerun hardening tests. |
| Shm validation gap | MEDIUM | Add size checks and corrupt-object tests; verify no production shm name is touched. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| SPSC ownership violation | Phase 9 | Ring tests plus source search for producer-side `pop()`. |
| Large callback tail | Phase 9 or 10 | Callback unit tests for >1024 frames. |
| Swift stop deadlock | Phase 10 | XCTest stop timeout/concurrent waiter tests. |
| Metrics data race | Phase 10 or 11 | Native tests/source audit proving atomic/double-buffer publication. |
| Shm validation gap | Phase 11 | Corrupt shm Catch2 tests. |
| Missing live proof | Phase 12 | `scripts/ci.sh`, `verify-installed-sync.sh`, `verify-hal-driver.sh`, `--shm-status`, and Cubase soak evidence. |

## Sources

- User-provided highest-priority bug/risk list.
- Local source audit and tests listed in `STACK.md`.
- v0.2 deferred items in `.planning/STATE.md`.

---
*Pitfalls research for: v0.3 Realtime Audio Hardening*
*Researched: 2026-06-12*
