#include "engine/BridgeMetrics.h"

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

BridgeMetrics MakeBridgeMetrics(double fillMs, double ratio, double ppm, uint64_t underruns,
                                uint64_t overruns, uint64_t xruns, double targetFillMs,
                                std::string_view srcQuality) {
  BridgeMetrics metrics;
  metrics.fillMs = fillMs;
  metrics.ratio = ratio;
  metrics.ppm = ppm;
  metrics.underruns = underruns;
  metrics.overruns = overruns;
  metrics.xruns = xruns;
  metrics.targetFillMs = targetFillMs;
  metrics.srcQuality = std::string(srcQuality);
  const double delay = SrcGroupDelayMsForCli(srcQuality);
  metrics.estimatedRtMs = fillMs + delay;
  if (metrics.estimatedRtMs < delay) {
    metrics.estimatedRtMs = delay;
  }
  return metrics;
}

std::string ToJsonLine(const BridgeMetrics& metrics) {
  char buffer[512];
  const int written = std::snprintf(
      buffer, sizeof(buffer),
      R"({"fill_ms":%.3f,"ratio":%.8f,"ppm":%.2f,"underruns":%llu,"overruns":%llu,"xruns":%llu,"estimated_rt_ms":%.3f,"target_fill_ms":%.3f,"src_quality":"%s"})",
      metrics.fillMs, metrics.ratio, metrics.ppm,
      static_cast<unsigned long long>(metrics.underruns),
      static_cast<unsigned long long>(metrics.overruns),
      static_cast<unsigned long long>(metrics.xruns), metrics.estimatedRtMs, metrics.targetFillMs,
      metrics.srcQuality.c_str());
  if (written < 0) {
    return "{}";
  }
  return std::string(buffer, static_cast<std::size_t>(written));
}

}  // namespace apm44
