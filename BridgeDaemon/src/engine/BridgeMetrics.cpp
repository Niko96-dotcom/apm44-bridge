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

BridgeMetrics MakeBridgeMetrics(const MetricsSnapshot& snapshot, double targetFillMs,
                                std::string_view srcQuality) {
  BridgeMetrics metrics = MakeBridgeMetrics(
      snapshot.fillMs, snapshot.smoothedRatio, snapshot.ppm, snapshot.underruns,
      snapshot.overruns, snapshot.xruns, targetFillMs, srcQuality);
  metrics.inputDroppedFrames = snapshot.inputDroppedFrames;
  metrics.producerOverrunEvents = snapshot.producerOverrunEvents;
  metrics.producerDroppedFrames = snapshot.producerDroppedFrames;
  metrics.producerNotReadyDroppedFrames = snapshot.producerNotReadyDroppedFrames;
  metrics.laneQueueDrops = snapshot.laneQueueDrops;
  metrics.laneTimestampMismatches = snapshot.laneTimestampMismatches;
  metrics.laneFrameMismatchDroppedFrames = snapshot.laneFrameMismatchDroppedFrames;
  metrics.consumerResets = snapshot.consumerResets;
  metrics.outputStarvationFrames = snapshot.outputStarvationFrames;
  return metrics;
}

std::string ToJsonLine(const BridgeMetrics& metrics) {
  char buffer[1024];
  const int written = std::snprintf(
      buffer, sizeof(buffer),
      R"({"fill_ms":%.3f,"ratio":%.8f,"ppm":%.2f,"underruns":%llu,"overruns":%llu,"xruns":%llu,"input_dropped_frames":%llu,"producer_overrun_events":%llu,"producer_dropped_frames":%llu,"producer_not_ready_dropped_frames":%llu,"lane_queue_drops":%llu,"lane_timestamp_mismatches":%llu,"lane_frame_mismatch_dropped_frames":%llu,"consumer_resets":%llu,"output_starvation_frames":%llu,"estimated_rt_ms":%.3f,"target_fill_ms":%.3f,"src_quality":"%s"})",
      metrics.fillMs, metrics.ratio, metrics.ppm,
      static_cast<unsigned long long>(metrics.underruns),
      static_cast<unsigned long long>(metrics.overruns),
      static_cast<unsigned long long>(metrics.xruns),
      static_cast<unsigned long long>(metrics.inputDroppedFrames),
      static_cast<unsigned long long>(metrics.producerOverrunEvents),
      static_cast<unsigned long long>(metrics.producerDroppedFrames),
      static_cast<unsigned long long>(metrics.producerNotReadyDroppedFrames),
      static_cast<unsigned long long>(metrics.laneQueueDrops),
      static_cast<unsigned long long>(metrics.laneTimestampMismatches),
      static_cast<unsigned long long>(metrics.laneFrameMismatchDroppedFrames),
      static_cast<unsigned long long>(metrics.consumerResets),
      static_cast<unsigned long long>(metrics.outputStarvationFrames),
      metrics.estimatedRtMs, metrics.targetFillMs,
      metrics.srcQuality.c_str());
  if (written < 0) {
    return "{}";
  }
  if (written >= static_cast<int>(sizeof(buffer))) {
    return "{}";
  }
  return std::string(buffer, static_cast<std::size_t>(written));
}

}  // namespace apm44
