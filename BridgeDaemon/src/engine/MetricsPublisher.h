#pragma once

#include <apm44/MetricsSnapshot.h>

#include <atomic>
#include <cstdint>

namespace apm44 {

// State for the metrics publisher. Lifted out of `BridgeEngine` so the
// publication contract can be tested without spinning up the full
// audio engine (which needs Core Audio device IDs and a real prepared
// ring). Every payload field is atomic, so the sequence counter never
// guards a racy non-atomic struct copy.
struct MetricsPublisherState {
  std::atomic<uint64_t> sequence{0};
  std::atomic<double> fillMs{0.0};
  std::atomic<double> smoothedRatio{1.0};
  std::atomic<double> ppm{0.0};
  std::atomic<uint64_t> underruns{0};
  std::atomic<uint64_t> overruns{0};
  std::atomic<uint64_t> xruns{0};
};

// Writer side (called from the realtime thread, e.g. inside
// `onOutput`'s `PublishGuard`). The sequence pattern:
//
//   1. Bump `sequence` to sequence+1 (odd) to signal a write in progress.
//   2. Store each field atomically.
//   3. Bump `sequence` to sequence+2 (even) to publish.
//
// Readers busy-wait until they see a stable even sequence number
// with no concurrent writer.
inline void PublishMetrics(MetricsPublisherState& state,
                           const MetricsSnapshot& next) {
  const uint64_t sequence = state.sequence.load(std::memory_order_relaxed);
  state.sequence.store(sequence + 1U, std::memory_order_release);
  state.fillMs.store(next.fillMs, std::memory_order_relaxed);
  state.smoothedRatio.store(next.smoothedRatio, std::memory_order_relaxed);
  state.ppm.store(next.ppm, std::memory_order_relaxed);
  state.underruns.store(next.underruns, std::memory_order_relaxed);
  state.overruns.store(next.overruns, std::memory_order_relaxed);
  state.xruns.store(next.xruns, std::memory_order_relaxed);
  state.sequence.store(sequence + 2U, std::memory_order_release);
}

// Reader side (CLI JSON emitter, app UI consumer, control loop).
// Loops until it observes an even sequence with no torn read. The
// return value is a coherent `MetricsSnapshot` copy.
inline MetricsSnapshot ReadMetrics(const MetricsPublisherState& state) {
  for (;;) {
    const uint64_t sequenceBefore =
        state.sequence.load(std::memory_order_acquire);
    if (sequenceBefore & 1U) {
      // Writer in progress; retry.
      continue;
    }
    MetricsSnapshot copy;
    copy.fillMs = state.fillMs.load(std::memory_order_relaxed);
    copy.smoothedRatio = state.smoothedRatio.load(std::memory_order_relaxed);
    copy.ppm = state.ppm.load(std::memory_order_relaxed);
    copy.underruns = state.underruns.load(std::memory_order_relaxed);
    copy.overruns = state.overruns.load(std::memory_order_relaxed);
    copy.xruns = state.xruns.load(std::memory_order_relaxed);
    const uint64_t sequenceAfter =
        state.sequence.load(std::memory_order_acquire);
    if (sequenceBefore == sequenceAfter) {
      return copy;
    }
    // sequence changed under us; retry.
  }
}

}  // namespace apm44
