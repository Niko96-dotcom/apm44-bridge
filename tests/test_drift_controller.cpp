#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_approx.hpp>

#include "apm44/DriftController.h"

#include <algorithm>
#include <cmath>
#include <vector>

TEST_CASE("DriftController fill above target lowers SRC ratio", "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(662);
  drift.update(900, 512);
  REQUIRE(drift.currentPpm() < 0.0);
  REQUIRE(drift.currentPpm() >= -apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController fill below target raises SRC ratio", "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(662);
  drift.update(200, 512);
  REQUIRE(drift.currentPpm() > 0.0);
  REQUIRE(drift.currentPpm() <= apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController ppm clamp", "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(100);
  for (int i = 0; i < 5000; ++i) {
    drift.update(100000, 512);
  }
  REQUIRE(std::abs(drift.currentPpm()) <= apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController max ppm can be widened for virtual source pacing",
          "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(5000);
  drift.setMaxPpm(3000.0);

  for (int i = 0; i < 5000; ++i) {
    drift.update(0, 512);
  }

  REQUIRE(drift.currentPpm() > apm44::DriftController::kMaxPpm);
  REQUIRE(std::abs(drift.currentPpm()) <= 3000.0);
}

TEST_CASE("DriftController asks for meaningful catch-up when fill is very low",
          "[drift_controller]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(1323);

  drift.update(735, 512);

  REQUIRE(drift.currentPpm() >= 175.0);
  REQUIRE(drift.currentPpm() <= apm44::DriftController::kMaxPpm);
}

TEST_CASE("DriftController sustained skew stabilizes fill error", "[drift_controller]") {
  apm44::DriftController drift;
  constexpr std::size_t kTarget = 662;
  drift.setTargetFillFrames(kTarget);

  std::size_t fill = kTarget + 200;
  for (int i = 0; i < 2000; ++i) {
    (void)drift.update(fill, 512);
    const double ppm = drift.currentPpm();
    if (fill > kTarget) {
      fill = fill > 50 ? fill - static_cast<std::size_t>(std::abs(ppm) * 0.05) : kTarget;
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

namespace {

apm44::DriftController RunSchedule(const std::vector<std::size_t>& schedule,
                                   std::size_t totalFrames) {
  apm44::DriftController drift;
  drift.setTargetFillFrames(662);
  std::size_t rendered = 0;
  std::size_t index = 0;
  while (rendered < totalFrames) {
    const std::size_t frames =
        std::min(schedule[index % schedule.size()], totalFrames - rendered);
    drift.update(762, frames, 48000.0);
    rendered += frames;
    ++index;
  }
  return drift;
}

}  // namespace

TEST_CASE("DriftController response is callback-size invariant",
          "[drift_controller][time_based]") {
  const auto baseline = RunSchedule({512}, 48000);
  for (const std::size_t block : {64U, 128U, 256U, 1024U}) {
    const auto candidate = RunSchedule({block}, 48000);
    REQUIRE(candidate.currentPpm() == Catch::Approx(baseline.currentPpm()).margin(0.01));
    REQUIRE(candidate.smoothedRatio() ==
            Catch::Approx(baseline.smoothedRatio()).margin(1e-8));
  }

  const auto variable = RunSchedule({64, 1024, 128, 512, 256}, 48000);
  REQUIRE(variable.currentPpm() == Catch::Approx(baseline.currentPpm()).margin(0.01));
  REQUIRE(variable.smoothedRatio() ==
          Catch::Approx(baseline.smoothedRatio()).margin(1e-8));
}

TEST_CASE("DriftController clears saturated integral after underrun",
          "[drift_controller][rebuffer]") {
  apm44::DriftController drift;
  drift.setTargetFillFrames(662);
  for (int i = 0; i < 1000; ++i) {
    drift.update(0, 512);
  }
  REQUIRE(std::abs(drift.currentPpm()) > 100.0);

  drift.notifyUnderrun();
  REQUIRE(drift.currentPpm() == 0.0);
  REQUIRE(drift.smoothedRatio() == apm44::DriftController::kNominalRatio);
  REQUIRE(drift.underrunCount() == 1);
}
