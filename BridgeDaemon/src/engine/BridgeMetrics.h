#pragma once

#include <apm44/MetricsSnapshot.h>

#include <cstdint>
#include <string>
#include <string_view>

namespace apm44 {

// Documented group-delay estimates for honest RT latency (QA-03). Not zero.
inline constexpr double kSrcGroupDelayMediumMs = 1.5;
inline constexpr double kSrcGroupDelayHighMs = 2.5;
inline constexpr double kSrcGroupDelayBestMs = 3.0;

double SrcGroupDelayMsForCli(std::string_view srcQuality);

struct BridgeMetrics {
  double fillMs = 0.0;
  double ratio = 0.0;
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
  double estimatedRtMs = 0.0;
  double targetFillMs = 15.0;
  std::string srcQuality = "medium";
};

BridgeMetrics MakeBridgeMetrics(double fillMs, double ratio, double ppm, uint64_t underruns,
                                uint64_t overruns, uint64_t xruns, double targetFillMs,
                                std::string_view srcQuality);
BridgeMetrics MakeBridgeMetrics(const MetricsSnapshot& snapshot, double targetFillMs,
                                std::string_view srcQuality);

std::string ToJsonLine(const BridgeMetrics& metrics);

}  // namespace apm44
