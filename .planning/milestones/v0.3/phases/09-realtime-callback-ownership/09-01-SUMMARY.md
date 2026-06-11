---
phase: 09
plan: 01
subsystem: realtime-callbacks
tags: [rt, spsc, overrun-policy]
requirements: [RT-01, RT-02, RT-05]
provides:
  - "Producer-side overrun policy: drop-new-input, DriftController notification"
  - "BridgeInputOverrun.h no longer calls ring.pop() from the producer path"
key_files:
  - BridgeDaemon/src/engine/BridgeInputOverrun.h
  - tests/test_planar_ring_buffer.cpp
  - tests/test_hardening_audit.cpp
---

# Plan 09-01 Summary

## What was done

- **BridgeInputOverrun.h** — `DropOldestThenPush` no longer pops frames
  from the ring. It now calls `ring.push()` once, and if the accepted
  count is less than the requested frames, calls
  `drift.notifyOverrun()`. The function signature is unchanged so the
  caller in `BridgeEngine.cpp` is untouched. A header comment documents
  the new policy (drop-new-input) and explicitly forbids producer-side
  `pop`.
- **tests/test_planar_ring_buffer.cpp** — added two new test cases
  exercising the producer path:
  - `ProducerDropOldestThenPushDropsUnacceptedAndNotifiesOverrun` —
    pushes into a full ring, asserts no producer pop, asserts the
    consumer-visible fill is preserved, asserts the overrun counter is
    bumped.
  - `ProducerPathSucceedsWhenRingHasCapacity` — baseline happy-path
    push with no overrun signal.
- **tests/test_hardening_audit.cpp** — the existing
  `PlanarRingBuffer drop-oldest overrun preserves indices` test was
  updated to assert the new contract: the producer drops the unaccepted
  incoming tail and the consumer-visible fill (and the original frames)
  are preserved unchanged. Test still uses a stack-allocated
  `PlanarRingBuffer`; no `/apm44_bridge_ring` is touched (RT-05).

## Test results

```
test_planar_ring_buffer: All tests passed (10017 assertions in 7 test cases)
test_hardening_audit:    All tests passed (16 assertions in 4 test cases)
```

## Deviations

- The hardening-audit test case was renamed and its expectations changed
  to match the new RT-01/RT-02 contract. The old test asserted that the
  producer would `pop` an oldest frame to make room — the new contract
  forbids that. This is a deliberate consequence of the policy change,
  not a bug. The new assertions still cover the same memory regions
  (consumer-visible fill after a producer overrun) and add stronger
  guarantees (the original frames are exactly preserved, and the
  incoming tail is verifiably dropped).

## Self-check

- [x] `grep -n "ring.pop\|PlanarRingBuffer::pop" BridgeInputOverrun.h`
      returns no matches.
- [x] The producer-side overrun policy is documented in the header
      comment.
- [x] New Catch2 test cases run and pass.
- [x] No file in the test path references `/apm44_bridge_ring`.
