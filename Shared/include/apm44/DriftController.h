#pragma once

#include <cstddef>
#include <cstdint>

namespace apm44 {

// PI drift controller: maps ring fill error to ppm adjustment on nominal SRC ratio.
// RT-safe in update() — no allocation, locks, or I/O.
class DriftController {
 public:
  static constexpr double kNominalRatio = 48000.0 / 44100.0;
  static constexpr double kMaxPpm = 500.0;

  void reset();
  void setTargetFillFrames(std::size_t frames);
  void setMaxPpm(double ppm);

  double update(std::size_t currentFillFrames, std::size_t outputFrames,
                double outputSampleRate = 48000.0);
  double currentPpm() const { return currentPpm_; }
  double smoothedRatio() const { return smoothedRatio_; }

  void notifyUnderrun();
  void notifyOverrun();
  uint64_t underrunCount() const { return underrunCount_; }
  uint64_t overrunCount() const { return overrunCount_; }

 private:
  void resetControlState();
  std::size_t targetFillFrames_ = 0;
  double integral_ = 0.0;
  double currentPpm_ = 0.0;
  double maxPpm_ = kMaxPpm;
  double smoothedRatio_ = kNominalRatio;
  uint64_t underrunCount_ = 0;
  uint64_t overrunCount_ = 0;
};

}  // namespace apm44
