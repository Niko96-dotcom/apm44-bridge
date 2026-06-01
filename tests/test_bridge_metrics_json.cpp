#include "engine/BridgeMetrics.h"

#include <catch2/catch_test_macros.hpp>

#include <cmath>
#include <string>

namespace {

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

}  // namespace

TEST_CASE("BridgeMetrics JSON contains required fields") {
  const auto metrics = apm44::MakeBridgeMetrics(15.2, 1.088435, 12.0, 1, 2, 3, 15.0, "medium");
  const std::string line = apm44::ToJsonLine(metrics);

  REQUIRE(Contains(line, "\"fill_ms\""));
  REQUIRE(Contains(line, "\"xruns\""));
  REQUIRE(Contains(line, "\"ratio\""));
  REQUIRE(Contains(line, "\"underruns\""));
  REQUIRE(Contains(line, "\"overruns\""));
  REQUIRE(Contains(line, "\"ppm\""));
  REQUIRE(Contains(line, "15.200"));
  REQUIRE(line.find('\n') == std::string::npos);
}

TEST_CASE("estimated_rt_ms equals fill_ms plus group delay") {
  const auto metrics = apm44::MakeBridgeMetrics(10.0, 1.0, 0.0, 0, 0, 0, 10.0, "medium");
  REQUIRE(std::abs(metrics.estimatedRtMs - (10.0 + apm44::kSrcGroupDelayMediumMs)) < 0.001);
  REQUIRE(metrics.estimatedRtMs > 0.0);
}
