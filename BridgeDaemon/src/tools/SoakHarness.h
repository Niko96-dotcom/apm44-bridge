#pragma once

#include <cstdint>

namespace apm44 {

struct SoakMetrics {
  double durationSec = 0.0;
  double meanFillMs = 0.0;
  double maxFillMs = 0.0;
  uint64_t underruns = 0;
  uint64_t overruns = 0;
  double finalPpm = 0.0;
  bool passed = false;
};

struct SoakOptions {
  double durationSec = 60.0;
  double skewPpm = 50.0;
  double targetFillMs = 15.0;
};

// Offline clock-skew soak using production ring + drift + libsamplerate (no HAL).
SoakMetrics RunSoakHarness(const SoakOptions& options);

}  // namespace apm44
