#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace apm44 {

// Snapshot of the realtime metrics that the CLI JSON emitter, the
// Swift app UI, and the control loop consume. Publication of this
// struct across threads must go through `MetricsPublisher` (a
// seqlock) — never copy it across threads directly. See
// `BridgeDaemon/src/engine/MetricsPublisher.h`.
//
// To add a counter: add the member here, add its row to
// `kMetricsCounterFields` below, fill it in
// `BridgeEngine::publishMetricsSnapshot`, and add its key to the Swift
// `BridgeMetricsSnapshot`. The publisher and the JSON line follow the table;
// tests/test_helper_contract.swift fails until the Swift key exists.
struct MetricsSnapshot {
  double fillMs = 0.0;
  double smoothedRatio = 1.0;
  double ppm = 0.0;
  uint64_t underruns = 0;
  uint64_t overruns = 0;
  uint64_t xruns = 0;
  uint64_t inputDroppedFrames = 0;
  uint64_t producerOverrunEvents = 0;
  uint64_t producerDroppedFrames = 0;
  uint64_t producerNotReadyDroppedFrames = 0;
  uint64_t laneQueueDrops = 0;
  uint64_t laneTimestampMismatches = 0;
  uint64_t laneFrameMismatchDroppedFrames = 0;
  uint64_t consumerResets = 0;
  uint64_t outputStarvationFrames = 0;
  uint64_t partialShortageEvents = 0;
  uint64_t converterResetEvents = 0;
  uint64_t rebufferEvents = 0;
  uint64_t recoveryFadeEvents = 0;

  bool operator==(const MetricsSnapshot&) const = default;
};

// One row per uint64 counter: its metrics JSON key (the contract with
// `BridgeMetricsSnapshot.CodingKeys`) and its member. Row order is the JSON
// key order and the publisher's atomic slot order.
struct MetricsCounterField {
  const char* jsonKey;
  uint64_t MetricsSnapshot::*member;
};

inline constexpr std::array kMetricsCounterFields{
    MetricsCounterField{"underruns", &MetricsSnapshot::underruns},
    MetricsCounterField{"overruns", &MetricsSnapshot::overruns},
    MetricsCounterField{"xruns", &MetricsSnapshot::xruns},
    MetricsCounterField{"input_dropped_frames", &MetricsSnapshot::inputDroppedFrames},
    MetricsCounterField{"producer_overrun_events", &MetricsSnapshot::producerOverrunEvents},
    MetricsCounterField{"producer_dropped_frames", &MetricsSnapshot::producerDroppedFrames},
    MetricsCounterField{"producer_not_ready_dropped_frames",
                        &MetricsSnapshot::producerNotReadyDroppedFrames},
    MetricsCounterField{"lane_queue_drops", &MetricsSnapshot::laneQueueDrops},
    MetricsCounterField{"lane_timestamp_mismatches", &MetricsSnapshot::laneTimestampMismatches},
    MetricsCounterField{"lane_frame_mismatch_dropped_frames",
                        &MetricsSnapshot::laneFrameMismatchDroppedFrames},
    MetricsCounterField{"consumer_resets", &MetricsSnapshot::consumerResets},
    MetricsCounterField{"output_starvation_frames", &MetricsSnapshot::outputStarvationFrames},
    MetricsCounterField{"partial_shortage_events", &MetricsSnapshot::partialShortageEvents},
    MetricsCounterField{"converter_reset_events", &MetricsSnapshot::converterResetEvents},
    MetricsCounterField{"rebuffer_events", &MetricsSnapshot::rebufferEvents},
    MetricsCounterField{"recovery_fade_events", &MetricsSnapshot::recoveryFadeEvents},
};

constexpr bool MetricsCounterFieldsAreDistinct() {
  for (std::size_t i = 0; i < kMetricsCounterFields.size(); ++i) {
    for (std::size_t j = i + 1; j < kMetricsCounterFields.size(); ++j) {
      if (kMetricsCounterFields[i].member == kMetricsCounterFields[j].member ||
          std::string_view(kMetricsCounterFields[i].jsonKey) ==
              std::string_view(kMetricsCounterFields[j].jsonKey)) {
        return false;
      }
    }
  }
  return true;
}

// Together these hold the table to exactly one row per counter: the
// snapshot is the three doubles plus one uint64 per row, and no row repeats.
static_assert(sizeof(MetricsSnapshot) ==
                  3 * sizeof(double) + kMetricsCounterFields.size() * sizeof(uint64_t),
              "every MetricsSnapshot counter needs one row in kMetricsCounterFields");
static_assert(MetricsCounterFieldsAreDistinct(),
              "kMetricsCounterFields repeats a member or a JSON key");

}  // namespace apm44
