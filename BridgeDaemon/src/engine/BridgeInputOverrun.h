#pragma once

#include <apm44/DriftController.h>
#include <apm44/PlanarRingBuffer.h>

namespace apm44 {

// Producer-side overrun policy (RT-01, RT-02):
//
// The input realtime path is the SPSC producer. It must NEVER call
// `PlanarRingBuffer::pop()` — that mutates consumer-owned state and
// crosses the ownership boundary (RT-01). When the ring is too full to
// accept the full incoming block, we drop the unaccepted tail of the
// incoming block (RT-02 — drop-new-input policy) and notify the drift
// controller so the overrun is recorded for metrics.
//
// The output consumer is the only path that may pop frames from the ring
// (see `VirtualDeviceFeed`).
//
// `dropScratch` is retained in the signature for ABI stability with the
// existing call site in `BridgeEngine.cpp`; it is no longer read.
inline void PushDroppingNewInput(PlanarRingBuffer& ring,
                                 float* /*dropScratch*/[2],
                                 DriftController& drift,
                                 const float* const channels[2],
                                 std::size_t frames) {
  const std::size_t accepted = ring.push(channels, frames);
  if (accepted < frames) {
    drift.notifyOverrun();
  }
}

}  // namespace apm44
