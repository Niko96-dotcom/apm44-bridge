#include "apm44/DriftController.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace apm44 {

namespace {

// Preserve the response of the original 512-frame/48 kHz tuning while making
// integration and smoothing advance in physical time.
constexpr double kProportionalGain = 0.35;
constexpr double kIntegralGain = 0.006;
constexpr double kIntegralClamp = 5000.0;
constexpr double kReferenceSeconds = 512.0 / 48000.0;
constexpr double kRatioSmoothingTimeConstantSeconds = 0.127932;

}  // namespace

void DriftController::reset() {
  resetControlState();
  underrunCount_ = 0;
  overrunCount_ = 0;
}

void DriftController::resetControlState() {
  integral_ = 0.0;
  currentPpm_ = 0.0;
  smoothedRatio_ = kNominalRatio;
}

void DriftController::setTargetFillFrames(std::size_t frames) {
  targetFillFrames_ = frames;
}

void DriftController::setMaxPpm(double ppm) {
  if (std::isfinite(ppm) && ppm > 0.0) {
    maxPpm_ = ppm;
  }
}

double DriftController::update(std::size_t currentFillFrames,
                               std::size_t outputFrames,
                               double outputSampleRate) {
  double fill = static_cast<double>(currentFillFrames);
  if (!std::isfinite(fill)) {
    fill = static_cast<double>(targetFillFrames_);
  }

  const double error = fill - static_cast<double>(targetFillFrames_);
  double elapsedSeconds = static_cast<double>(outputFrames) / outputSampleRate;
  if (!std::isfinite(elapsedSeconds) || elapsedSeconds <= 0.0) {
    elapsedSeconds = kReferenceSeconds;
  }
  integral_ += error * (elapsedSeconds / kReferenceSeconds);
  integral_ = std::clamp(integral_, -kIntegralClamp, kIntegralClamp);

  double ppm = -(kProportionalGain * error + kIntegralGain * integral_);
  ppm = std::clamp(ppm, -maxPpm_, maxPpm_);
  currentPpm_ = ppm;

  const double targetRatio = kNominalRatio * (1.0 + ppm / 1'000'000.0);
  const double smoothingAlpha =
      1.0 - std::exp(-elapsedSeconds / kRatioSmoothingTimeConstantSeconds);
  smoothedRatio_ += smoothingAlpha * (targetRatio - smoothedRatio_);
  return smoothedRatio_;
}

void DriftController::notifyUnderrun() { ++underrunCount_; }

void DriftController::resetAfterDiscontinuity() { resetControlState(); }

void DriftController::notifyOverrun() { ++overrunCount_; }

}  // namespace apm44
