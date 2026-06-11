#pragma once

#include <cstdint>

namespace apm44 {

// Snapshot of the realtime metrics that the CLI JSON emitter, the
// Swift app UI, and the control loop consume. Publication of this
// struct across threads must go through `MetricsPublisher` (a
// seqlock) — never copy it across threads directly. See
// `BridgeDaemon/src/engine/MetricsPublisher.h`.
struct MetricsSnapshot {
  double fillMs = 0.0;
  double smoothedRatio = 1.0;
  double ppm = 0.0;
  uint64_t underruns = 0;
  uint64_t overruns = 0;
  uint64_t xruns = 0;
};

}  // namespace apm44
