#include "tools/SoakHarness.h"

#include <cstdlib>
#include <iostream>
#include <string_view>

namespace {

void PrintUsage(const char* program) {
  std::cerr << "Usage: " << program
            << " [--duration-sec N] [--skew-ppm N] [--target-fill-ms N]\n"
            << "  Default: 60s duration, 50 ppm skew, 15 ms target fill\n";
}

double ParseDouble(const char* text, double fallback) {
  try {
    return std::stod(text);
  } catch (...) {
    return fallback;
  }
}

}  // namespace

int main(int argc, char* argv[]) {
  apm44::SoakOptions options{};

  for (int i = 1; i < argc; ++i) {
    const std::string_view arg{argv[i]};
    if (arg == "--help" || arg == "-h") {
      PrintUsage(argv[0]);
      return 0;
    }
    if (arg == "--duration-sec" && i + 1 < argc) {
      options.durationSec = ParseDouble(argv[++i], options.durationSec);
    } else if (arg == "--skew-ppm" && i + 1 < argc) {
      options.skewPpm = ParseDouble(argv[++i], options.skewPpm);
    } else if (arg == "--target-fill-ms" && i + 1 < argc) {
      options.targetFillMs = ParseDouble(argv[++i], options.targetFillMs);
    } else {
      std::cerr << "error: unknown option " << arg << "\n";
      PrintUsage(argv[0]);
      return 2;
    }
  }

  const apm44::SoakMetrics metrics = apm44::RunSoakHarness(options);
  std::cout << "duration_sec=" << metrics.durationSec << "\n"
            << "mean_fill_ms=" << metrics.meanFillMs << "\n"
            << "max_fill_ms=" << metrics.maxFillMs << "\n"
            << "underruns=" << metrics.underruns << "\n"
            << "overruns=" << metrics.overruns << "\n"
            << "final_ppm=" << metrics.finalPpm << "\n"
            << "passed=" << (metrics.passed ? "1" : "0") << "\n";

  return metrics.passed ? 0 : 1;
}
