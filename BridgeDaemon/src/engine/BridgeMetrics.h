#pragma once

#include <apm44/MetricsSnapshot.h>

#include <string>
#include <string_view>

namespace apm44 {

// Documented group-delay estimates for honest RT latency (QA-03). Not zero.
inline constexpr double kSrcGroupDelayMediumMs = 1.5;
inline constexpr double kSrcGroupDelayHighMs = 2.5;
inline constexpr double kSrcGroupDelayBestMs = 3.0;

double SrcGroupDelayMsForCli(std::string_view srcQuality);

// One metrics JSON line: the published snapshot plus the values the CLI adds.
struct BridgeMetrics {
  MetricsSnapshot snapshot;
  double estimatedRtMs = 0.0;
  double targetFillMs = 15.0;
  std::string srcQuality = "medium";
};

BridgeMetrics MakeBridgeMetrics(const MetricsSnapshot& snapshot, double targetFillMs,
                                std::string_view srcQuality);

std::string ToJsonLine(const BridgeMetrics& metrics);

}  // namespace apm44
