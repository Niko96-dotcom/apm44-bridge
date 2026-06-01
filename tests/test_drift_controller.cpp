#include <catch2/catch_test_macros.hpp>

#include "apm44/DriftController.h"

TEST_CASE("DriftController fill above target yields positive ppm", "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(662);
  drift.update(900);
  REQUIRE(drift.currentPpm() > 0.0);
  REQUIRE(drift.currentPpm() <= apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController fill below target yields negative ppm", "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(662);
  drift.update(200);
  REQUIRE(drift.currentPpm() < 0.0);
  REQUIRE(drift.currentPpm() >= -apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController ppm clamp", "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(100);
  for (int i = 0; i < 5000; ++i) {
    drift.update(100000);
  }
  REQUIRE(std::abs(drift.currentPpm()) <= apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController sustained skew stabilizes fill error", "[drift_controller]") {
  apm44::DriftController drift;
  constexpr std::size_t kTarget = 662;
  drift.setTargetFillFrames(kTarget);

  std::size_t fill = kTarget + 200;
  for (int i = 0; i < 2000; ++i) {
    (void)drift.update(fill);
    const double ppm = drift.currentPpm();
    if (fill > kTarget) {
      fill = fill > 50 ? fill - static_cast<std::size_t>(ppm * 0.05) : kTarget;
    }
  }
  REQUIRE(std::abs(static_cast<double>(fill) - static_cast<double>(kTarget)) <
          static_cast<double>(kTarget) * 0.5);
}

TEST_CASE("DriftController underrun and overrun counters", "[drift_controller]") {
  apm44::DriftController drift;
  REQUIRE(drift.underrunCount() == 0);
  REQUIRE(drift.overrunCount() == 0);
  drift.notifyUnderrun();
  drift.notifyUnderrun();
  drift.notifyOverrun();
  REQUIRE(drift.underrunCount() == 2);
  REQUIRE(drift.overrunCount() == 1);
}
