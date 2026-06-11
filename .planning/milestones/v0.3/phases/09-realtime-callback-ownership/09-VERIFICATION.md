---
phase: 09
status: passed
verified_at: 2026-06-12
verifier: gsd-verifier
---

# Phase 9: Realtime Callback Ownership — Verification

## Success criteria check

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Input overrun handling never calls `PlanarRingBuffer::pop()` from the producer path | **PASS** — `BridgeInputOverrun.h` rewritten; producer invokes `push` once and surfaces overruns via `drift.notifyOverrun()` |
| 2 | The chosen overrun behaviour is documented in code/tests and either drops incoming frames or performs oldest-frame trimming only from the output side | **PASS** — header comment in `BridgeInputOverrun.h` documents drop-new-input policy; tests assert the contract |
| 3 | Interleaved and non-interleaved output callbacks larger than the scratch capacity render or explicitly silence every actual frame | **PASS** — `OutputIoProc` (interleaved + non-interleaved) zeros the `[framesToRender, requestedFrames)` tail of every destination buffer |
| 4 | Native regression tests cover the selected overrun policy and oversized callback behaviour without touching `/apm44_bridge_ring` | **PASS** — all Phase 9 tests use stack-allocated `PlanarRingBuffer` instances and isolated shm names; `grep -n "apm44_bridge_ring" tests/test_io_proc_callbacks.cpp tests/test_planar_ring_buffer.cpp tests/test_hardening_audit.cpp` returns no matches |

## Test run

```
ctest --output-on-failure
100% tests passed, 0 tests failed out of 19
```

Phase 9 specific cases:

- `test_planar_ring_buffer` (7 cases, 10017 assertions) — covers the
  producer push path including the new drop-input overrun contract.
- `test_io_proc_callbacks` (4 cases, 1664 assertions) — covers
  oversized interleaved + non-interleaved output callback tail
  silencing, the within-capacity happy path, and the scratch-capacity
  boundary.
- `test_hardening_audit` (4 cases, 16 assertions) — the
  `drop-input overrun preserves consumer-visible fill` case verifies
  the new contract end-to-end (push 3, attempt to push 2 more, consumer
  reads the original 3 unchanged, no producer-side `pop`).

## Code review flags

None outstanding.

## Must-haves derived from goal-backward

| Must-have | Where it's proven |
|-----------|-------------------|
| Producer path never mutates consumer-owned state | `grep -n "ring.pop\|PlanarRingBuffer::pop" BridgeInputOverrun.h` → no matches; `test_planar_ring_buffer.cpp` "ProducerDropOldestThenPushDropsUnacceptedAndNotifiesOverrun" |
| Selected overrun policy is documented and tested | Header comment in `BridgeInputOverrun.h`; `test_hardening_audit.cpp` and `test_planar_ring_buffer.cpp` |
| Output callbacks render or silence every frame | `IoProcHandlers.cpp` interleaved + non-interleaved tail-silence loops; `test_io_proc_callbacks.cpp` (4 cases) |
| Tests do not touch `/apm44_bridge_ring` | `grep` returns no matches; all new tests use stack-allocated `PlanarRingBuffer` |

## Result

**Phase 9 status: passed.**

All five RT-* requirements are satisfied with code changes, native
tests, and matching test runs. The producer path no longer crosses the
SPSC ownership boundary, oversized output callbacks are safe, and no
test reaches into production shm.
