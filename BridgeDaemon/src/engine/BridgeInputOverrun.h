#pragma once

#include <apm44/PlanarRingBuffer.h>

namespace apm44 {

// Producer-side overrun policy (RT-01, RT-02):
//
// The input realtime path is the SPSC producer. It must NEVER call
// `PlanarRingBuffer::pop()` — that mutates consumer-owned state and
// crosses the ownership boundary (RT-01). When the ring is too full to
// accept the full incoming block, we drop the unaccepted tail of the
// incoming block (RT-02 — drop-new-input policy) and return true so
// the caller can record the input-side overrun without mutating
// output-owned drift state.
//
// The output consumer is the only path that may pop frames from the ring
// (see `VirtualDeviceFeed`).
inline bool PushDroppingNewInput(PlanarRingBuffer& ring,
                                 const float* const channels[2],
                                 std::size_t frames) {
  const std::size_t accepted = ring.push(channels, frames);
  return accepted < frames;
}

}  // namespace apm44
