#pragma once

#include <apm44/MetricsSnapshot.h>

#include <atomic>
#include <cstdint>

namespace apm44 {

// State for the metrics seqlock. Lifted out of `BridgeEngine` so the
// publication contract can be tested without spinning up the full
// audio engine (which needs Core Audio device IDs and a real
// prepared ring). The seqlock is the data-race-free mechanism behind
// METR-01; it is used by both the realtime writer (RT thread) and the
// CLI/control/UI readers.
struct MetricsPublisherState {
  std::atomic<uint32_t> seq{0};
  MetricsSnapshot snapshot{};
};

// Writer side (called from the realtime thread, e.g. inside
// `onOutput`'s `PublishGuard`). The seqlock pattern:
//
//   1. Bump `seq` to seq+1 (odd) to signal a write in progress.
//   2. Copy the new snapshot into the shared state.
//   3. Bump `seq` to seq+2 (even) to publish.
//
// Readers busy-wait until they see a stable even sequence number
// with no concurrent writer.
inline void PublishMetrics(MetricsPublisherState& state,
                           const MetricsSnapshot& next) {
  const uint32_t seq = state.seq.load(std::memory_order_relaxed);
  state.seq.store(seq + 1U, std::memory_order_release);
  state.snapshot = next;
  state.seq.store(seq + 2U, std::memory_order_release);
}

// Reader side (CLI JSON emitter, app UI consumer, control loop).
// Loops until it observes an even sequence with no torn read. The
// return value is a coherent `MetricsSnapshot` copy.
inline MetricsSnapshot ReadMetrics(const MetricsPublisherState& state) {
  for (;;) {
    const uint32_t seqBefore =
        state.seq.load(std::memory_order_acquire);
    if (seqBefore & 1U) {
      // Writer in progress; retry.
      continue;
    }
    const MetricsSnapshot copy = state.snapshot;
    const uint32_t seqAfter =
        state.seq.load(std::memory_order_acquire);
    if (seqBefore == seqAfter) {
      return copy;
    }
    // seq changed under us; retry.
  }
}

}  // namespace apm44
