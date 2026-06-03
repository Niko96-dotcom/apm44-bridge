#include "apm44/InputFrameDemand.h"

#include "apm44/DriftController.h"

#include <cmath>

namespace apm44 {

namespace {

constexpr double kIntegerBoundaryEpsilon = 1e-9;

}  // namespace

void InputFrameDemand::reset() { fractionalFrames_ = 0.0; }

std::size_t InputFrameDemand::consume(std::size_t outputFrames, double srcRatio) {
  if (outputFrames == 0) {
    return 0;
  }
  if (!std::isfinite(srcRatio) || srcRatio <= 0.0) {
    srcRatio = DriftController::kNominalRatio;
  }

  const double exactFrames = static_cast<double>(outputFrames) / srcRatio + fractionalFrames_;
  const auto wholeFrames =
      static_cast<std::size_t>(std::floor(exactFrames + kIntegerBoundaryEpsilon));
  fractionalFrames_ = exactFrames - static_cast<double>(wholeFrames);
  return wholeFrames;
}

}  // namespace apm44
