#include <catch2/catch_test_macros.hpp>

#include "tools/SoakHarness.h"

TEST_CASE("SoakHarness 5s fast skew profile", "[soak]") {
  apm44::SoakOptions options;
  options.durationSec = 5.0;
  options.skewPpm = 50.0;
  options.targetFillMs = 15.0;

  const apm44::SoakMetrics metrics = apm44::RunSoakHarness(options);
  REQUIRE(metrics.durationSec >= 4.5);
  REQUIRE(metrics.underruns == 0);
  REQUIRE(metrics.overruns == 0);
  REQUIRE(metrics.maxFillMs <= options.targetFillMs * 2.0 + 5.0);
  REQUIRE(metrics.passed);
}
