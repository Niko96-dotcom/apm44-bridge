#pragma once

#include <apm44/MetricsSnapshot.h>

#include <atomic>
#include <bit>
#include <cstdint>

namespace apm44 {

inline uint64_t PackMetricDouble(double value) {
  return std::bit_cast<uint64_t>(value);
}

inline double UnpackMetricDouble(uint64_t bits) {
  return std::bit_cast<double>(bits);
}

// One realtime writer publishes to non-realtime readers. Payload fields remain
// atomic so even a discarded, overlapping read is free of data races.
struct MetricsPublisherState {
  std::atomic<uint64_t> sequence{0};
  std::atomic<uint64_t> fillMsBits{PackMetricDouble(0.0)};
  std::atomic<uint64_t> smoothedRatioBits{PackMetricDouble(1.0)};
  std::atomic<uint64_t> ppmBits{PackMetricDouble(0.0)};
  std::atomic<uint64_t> underruns{0};
  std::atomic<uint64_t> overruns{0};
  std::atomic<uint64_t> xruns{0};
  std::atomic<uint64_t> inputDroppedFrames{0};
  std::atomic<uint64_t> producerOverrunEvents{0};
  std::atomic<uint64_t> producerDroppedFrames{0};
  std::atomic<uint64_t> producerNotReadyDroppedFrames{0};
  std::atomic<uint64_t> laneQueueDrops{0};
  std::atomic<uint64_t> laneTimestampMismatches{0};
  std::atomic<uint64_t> laneFrameMismatchDroppedFrames{0};
  std::atomic<uint64_t> consumerResets{0};
  std::atomic<uint64_t> outputStarvationFrames{0};
  std::atomic<uint64_t> partialShortageEvents{0};
  std::atomic<uint64_t> converterResetEvents{0};
  std::atomic<uint64_t> rebufferEvents{0};
  std::atomic<uint64_t> recoveryFadeEvents{0};
};

static_assert(std::atomic<uint64_t>::is_always_lock_free,
              "MetricsPublisherState requires lock-free uint64_t atomics");

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
  state.sequence.store(sequence + 1U, std::memory_order_relaxed);
  // Publish the odd sequence before any new payload field can be observed.
  std::atomic_thread_fence(std::memory_order_release);
  state.fillMsBits.store(PackMetricDouble(next.fillMs), std::memory_order_relaxed);
  state.smoothedRatioBits.store(PackMetricDouble(next.smoothedRatio), std::memory_order_relaxed);
  state.ppmBits.store(PackMetricDouble(next.ppm), std::memory_order_relaxed);
  state.underruns.store(next.underruns, std::memory_order_relaxed);
  state.overruns.store(next.overruns, std::memory_order_relaxed);
  state.xruns.store(next.xruns, std::memory_order_relaxed);
  state.inputDroppedFrames.store(next.inputDroppedFrames, std::memory_order_relaxed);
  state.producerOverrunEvents.store(next.producerOverrunEvents, std::memory_order_relaxed);
  state.producerDroppedFrames.store(next.producerDroppedFrames, std::memory_order_relaxed);
  state.producerNotReadyDroppedFrames.store(next.producerNotReadyDroppedFrames,
                                            std::memory_order_relaxed);
  state.laneQueueDrops.store(next.laneQueueDrops, std::memory_order_relaxed);
  state.laneTimestampMismatches.store(next.laneTimestampMismatches,
                                      std::memory_order_relaxed);
  state.laneFrameMismatchDroppedFrames.store(next.laneFrameMismatchDroppedFrames,
                                              std::memory_order_relaxed);
  state.consumerResets.store(next.consumerResets, std::memory_order_relaxed);
  state.outputStarvationFrames.store(next.outputStarvationFrames, std::memory_order_relaxed);
  state.partialShortageEvents.store(next.partialShortageEvents, std::memory_order_relaxed);
  state.converterResetEvents.store(next.converterResetEvents, std::memory_order_relaxed);
  state.rebufferEvents.store(next.rebufferEvents, std::memory_order_relaxed);
  state.recoveryFadeEvents.store(next.recoveryFadeEvents, std::memory_order_relaxed);
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
    copy.fillMs = UnpackMetricDouble(state.fillMsBits.load(std::memory_order_relaxed));
    copy.smoothedRatio =
        UnpackMetricDouble(state.smoothedRatioBits.load(std::memory_order_relaxed));
    copy.ppm = UnpackMetricDouble(state.ppmBits.load(std::memory_order_relaxed));
    copy.underruns = state.underruns.load(std::memory_order_relaxed);
    copy.overruns = state.overruns.load(std::memory_order_relaxed);
    copy.xruns = state.xruns.load(std::memory_order_relaxed);
    copy.inputDroppedFrames = state.inputDroppedFrames.load(std::memory_order_relaxed);
    copy.producerOverrunEvents = state.producerOverrunEvents.load(std::memory_order_relaxed);
    copy.producerDroppedFrames = state.producerDroppedFrames.load(std::memory_order_relaxed);
    copy.producerNotReadyDroppedFrames =
        state.producerNotReadyDroppedFrames.load(std::memory_order_relaxed);
    copy.laneQueueDrops = state.laneQueueDrops.load(std::memory_order_relaxed);
    copy.laneTimestampMismatches =
        state.laneTimestampMismatches.load(std::memory_order_relaxed);
    copy.laneFrameMismatchDroppedFrames =
        state.laneFrameMismatchDroppedFrames.load(std::memory_order_relaxed);
    copy.consumerResets = state.consumerResets.load(std::memory_order_relaxed);
    copy.outputStarvationFrames =
        state.outputStarvationFrames.load(std::memory_order_relaxed);
    copy.partialShortageEvents =
        state.partialShortageEvents.load(std::memory_order_relaxed);
    copy.converterResetEvents =
        state.converterResetEvents.load(std::memory_order_relaxed);
    copy.rebufferEvents = state.rebufferEvents.load(std::memory_order_relaxed);
    copy.recoveryFadeEvents =
        state.recoveryFadeEvents.load(std::memory_order_relaxed);
    // If a field came from a newer write, its release fence makes that write's
    // odd sequence visible before this final check, forcing a retry.
    std::atomic_thread_fence(std::memory_order_acquire);
    const uint64_t sequenceAfter =
        state.sequence.load(std::memory_order_relaxed);
    if (sequenceBefore == sequenceAfter) {
      return copy;
    }
    // sequence changed under us; retry.
  }
}

}  // namespace apm44
