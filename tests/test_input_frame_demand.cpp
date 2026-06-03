#include <catch2/catch_test_macros.hpp>

#include "apm44/DriftController.h"
#include "apm44/InputFrameDemand.h"

#include <algorithm>

namespace {

std::size_t ConsumeOneOutputSecond(apm44::InputFrameDemand& demand,
                                   std::size_t blockFrames,
                                   double ratio) {
  std::size_t outputRemaining = 48000;
  std::size_t inputFrames = 0;
  while (outputRemaining > 0) {
    const std::size_t frames = std::min(blockFrames, outputRemaining);
    inputFrames += demand.consume(frames, ratio);
    outputRemaining -= frames;
  }
  return inputFrames;
}

}  // namespace

TEST_CASE("InputFrameDemand preserves nominal 44100 rate across callback sizes",
          "[input_frame_demand]") {
  for (std::size_t blockFrames : {128u, 256u, 512u, 1024u}) {
    apm44::InputFrameDemand demand;
    const std::size_t inputFrames =
        ConsumeOneOutputSecond(demand, blockFrames, apm44::DriftController::kNominalRatio);
    REQUIRE(inputFrames == 44100);
  }
}

TEST_CASE("InputFrameDemand consumes more input when SRC ratio is reduced",
          "[input_frame_demand]") {
  apm44::InputFrameDemand nominalDemand;
  apm44::InputFrameDemand fasterDemand;

  const std::size_t nominal =
      ConsumeOneOutputSecond(nominalDemand, 512, apm44::DriftController::kNominalRatio);
  const double lowerRatio = apm44::DriftController::kNominalRatio * (1.0 - 500.0 / 1'000'000.0);
  const std::size_t faster = ConsumeOneOutputSecond(fasterDemand, 512, lowerRatio);

  REQUIRE(faster > nominal);
}
