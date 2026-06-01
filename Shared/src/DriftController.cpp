#include "apm44/DriftController.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace apm44 {

namespace {

// Tuned for ~512-frame output blocks @ 48 kHz. Gentler ratio tracking reduces
// audible SRC micro-steps (occasional clicks under HAL + host jitter).
constexpr double kProportionalGain = 0.05;
constexpr double kIntegralGain = 0.0015;
constexpr double kIntegralClamp = 5000.0;
constexpr double kRatioSmoothingAlpha = 0.025;

}  // namespace

void DriftController::reset() {
  integral_ = 0.0;
  currentPpm_ = 0.0;
  smoothedRatio_ = kNominalRatio;
  underrunCount_ = 0;
  overrunCount_ = 0;
}

void DriftController::setTargetFillFrames(std::size_t frames) {
  targetFillFrames_ = frames;
}

double DriftController::update(std::size_t currentFillFrames) {
  double fill = static_cast<double>(currentFillFrames);
  if (!std::isfinite(fill)) {
    fill = static_cast<double>(targetFillFrames_);
  }

  const double error = fill - static_cast<double>(targetFillFrames_);
  integral_ += error;
  integral_ = std::clamp(integral_, -kIntegralClamp, kIntegralClamp);

  double ppm = kProportionalGain * error + kIntegralGain * integral_;
  ppm = std::clamp(ppm, -kMaxPpm, kMaxPpm);
  currentPpm_ = ppm;

  const double targetRatio = kNominalRatio * (1.0 + ppm / 1'000'000.0);
  smoothedRatio_ += kRatioSmoothingAlpha * (targetRatio - smoothedRatio_);
  return smoothedRatio_;
}

void DriftController::notifyUnderrun() { ++underrunCount_; }

void DriftController::notifyOverrun() { ++overrunCount_; }

}  // namespace apm44
