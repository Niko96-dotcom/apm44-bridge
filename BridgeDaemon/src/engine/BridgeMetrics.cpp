#include "engine/BridgeMetrics.h"

#include <cstddef>
#include <cstdio>
#include <string>
#include <string_view>

namespace apm44 {

double SrcGroupDelayMsForCli(std::string_view srcQuality) {
  if (srcQuality == "best") {
    return kSrcGroupDelayBestMs;
  }
  if (srcQuality == "high") {
    return kSrcGroupDelayHighMs;
  }
  return kSrcGroupDelayMediumMs;
}

BridgeMetrics MakeBridgeMetrics(const MetricsSnapshot& snapshot, double targetFillMs,
                                std::string_view srcQuality) {
  BridgeMetrics metrics;
  metrics.snapshot = snapshot;
  metrics.targetFillMs = targetFillMs;
  metrics.srcQuality = std::string(srcQuality);
  const double delay = SrcGroupDelayMsForCli(srcQuality);
  metrics.estimatedRtMs = snapshot.fillMs + delay;
  if (metrics.estimatedRtMs < delay) {
    metrics.estimatedRtMs = delay;
  }
  return metrics;
}

// Writes the line piece by piece into one fixed buffer. A line that does not
// fit fails closed as "{}", exactly as one snprintf of the whole line would.
std::string ToJsonLine(const BridgeMetrics& metrics) {
  char buffer[1024];
  std::size_t used = 0;
  const auto fits = [&](int written) {
    if (written < 0 || static_cast<std::size_t>(written) >= sizeof(buffer) - used) {
      return false;
    }
    used += static_cast<std::size_t>(written);
    return true;
  };

  const MetricsSnapshot& snapshot = metrics.snapshot;
  if (!fits(std::snprintf(buffer, sizeof(buffer), R"({"fill_ms":%.3f,"ratio":%.8f,"ppm":%.2f)",
                          snapshot.fillMs, snapshot.smoothedRatio, snapshot.ppm))) {
    return "{}";
  }
  for (const MetricsCounterField& field : kMetricsCounterFields) {
    if (!fits(std::snprintf(buffer + used, sizeof(buffer) - used, R"(,"%s":%llu)",
                            field.jsonKey,
                            static_cast<unsigned long long>(snapshot.*field.member)))) {
      return "{}";
    }
  }
  if (!fits(std::snprintf(buffer + used, sizeof(buffer) - used,
                          R"(,"estimated_rt_ms":%.3f,"target_fill_ms":%.3f,"src_quality":"%s"})",
                          metrics.estimatedRtMs, metrics.targetFillMs,
                          metrics.srcQuality.c_str()))) {
    return "{}";
  }
  return std::string(buffer, used);
}

}  // namespace apm44
