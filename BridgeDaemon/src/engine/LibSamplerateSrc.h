#pragma once

#include <samplerate.h>

#include <cstddef>
#include <vector>

namespace apm44 {

class LibSamplerateSrc {
 public:
  enum class Quality { Medium, High, Best };

  LibSamplerateSrc() = default;
  ~LibSamplerateSrc();

  LibSamplerateSrc(const LibSamplerateSrc&) = delete;
  LibSamplerateSrc& operator=(const LibSamplerateSrc&) = delete;

  bool prepare(Quality quality = Quality::Medium);
  void setRatio(double ratio);
  bool process(const float* const inputChannels[2], std::size_t inputFrames,
               float* const outputChannels[2], std::size_t outputCapacity,
               std::size_t& outputFramesWritten);
  // Drains SRC filter delay after the final chunk of a stream (tests only).
  bool flush(float* const outputChannels[2], std::size_t outputCapacity,
             std::size_t& outputFramesWritten);
  bool reset();
  double nominalRatio() const { return lastRatio_; }

 private:
  static int QualityToConverterType(Quality quality);

  SRC_STATE* state_ = nullptr;
  double lastRatio_ = 48000.0 / 44100.0;
  std::size_t maxInputFrames_ = 0;
  std::size_t maxOutputFrames_ = 0;
  std::size_t maxPendingFrames_ = 0;
  std::size_t pendingInputFrames_ = 0;
  std::vector<float> inputInterleaved_;
  std::vector<float> outputInterleaved_;
  std::vector<float> pendingInterleaved_;
};

}  // namespace apm44
