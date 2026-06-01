#include "engine/LibSamplerateSrc.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace apm44 {

namespace {

constexpr double kRatioEpsilon = 1e-9;
constexpr std::size_t kMaxBlockFrames = 1024;

}  // namespace

LibSamplerateSrc::~LibSamplerateSrc() {
  if (state_ != nullptr) {
    src_delete(state_);
    state_ = nullptr;
  }
}

int LibSamplerateSrc::QualityToConverterType(Quality quality) {
  switch (quality) {
    case Quality::Best:
      return SRC_SINC_BEST_QUALITY;
    case Quality::High:
      return SRC_SINC_BEST_QUALITY;
    case Quality::Medium:
    default:
      return SRC_SINC_MEDIUM_QUALITY;
  }
}

bool LibSamplerateSrc::prepare(Quality quality) {
  if (state_ != nullptr) {
    return true;
  }

  int error = 0;
  state_ = src_new(QualityToConverterType(quality), 2, &error);
  if (state_ == nullptr || error != 0) {
    return false;
  }

  maxInputFrames_ = kMaxBlockFrames;
  maxOutputFrames_ =
      static_cast<std::size_t>(std::ceil(static_cast<double>(maxInputFrames_) * (48000.0 / 44100.0))) +
      32;
  inputInterleaved_.resize(maxInputFrames_ * 2);
  outputInterleaved_.resize(maxOutputFrames_ * 2);
  lastRatio_ = 48000.0 / 44100.0;
  src_set_ratio(state_, lastRatio_);
  return true;
}

void LibSamplerateSrc::setRatio(double ratio) {
  if (state_ == nullptr || !std::isfinite(ratio) || ratio <= 0.0) {
    return;
  }
  if (std::abs(ratio - lastRatio_) < kRatioEpsilon) {
    return;
  }
  src_set_ratio(state_, ratio);
  lastRatio_ = ratio;
}

bool LibSamplerateSrc::process(const float* const inputChannels[2], std::size_t inputFrames,
                               float* const outputChannels[2], std::size_t outputCapacity,
                               std::size_t& outputFramesWritten) {
  outputFramesWritten = 0;
  if (state_ == nullptr || inputFrames == 0 || outputCapacity == 0) {
    return false;
  }
  if (inputFrames > maxInputFrames_ || outputCapacity > maxOutputFrames_) {
    return false;
  }

  for (std::size_t i = 0; i < inputFrames; ++i) {
    inputInterleaved_[i * 2 + 0] = inputChannels[0][i];
    inputInterleaved_[i * 2 + 1] = inputChannels[1][i];
  }

  long inOffset = 0;
  long outOffset = 0;
  long inRemaining = static_cast<long>(inputFrames);
  const long outCapacity = static_cast<long>(outputCapacity);

  while (inRemaining > 0 && outOffset < outCapacity) {
    SRC_DATA data{};
    data.data_in = inputInterleaved_.data() + static_cast<std::size_t>(inOffset) * 2;
    data.data_out = outputInterleaved_.data() + static_cast<std::size_t>(outOffset) * 2;
    data.input_frames = inRemaining;
    data.output_frames = outCapacity - outOffset;
    data.end_of_input = 0;
    data.src_ratio = lastRatio_;

    if (src_process(state_, &data) != 0) {
      return false;
    }

    inOffset += data.input_frames_used;
    inRemaining -= data.input_frames_used;
    outOffset += data.output_frames_gen;

    if (data.input_frames_used == 0 && data.output_frames_gen == 0) {
      break;
    }
  }

  outputFramesWritten = static_cast<std::size_t>(outOffset);
  for (std::size_t i = 0; i < outputFramesWritten; ++i) {
    outputChannels[0][i] = outputInterleaved_[i * 2 + 0];
    outputChannels[1][i] = outputInterleaved_[i * 2 + 1];
  }
  return outputFramesWritten > 0;
}

bool LibSamplerateSrc::flush(float* const outputChannels[2], std::size_t outputCapacity,
                             std::size_t& outputFramesWritten) {
  outputFramesWritten = 0;
  if (state_ == nullptr || outputCapacity == 0 || outputCapacity > maxOutputFrames_) {
    return false;
  }

  SRC_DATA data{};
  data.data_in = inputInterleaved_.data();
  data.data_out = outputInterleaved_.data();
  data.input_frames = 0;
  data.output_frames = static_cast<long>(outputCapacity);
  data.end_of_input = 1;
  data.src_ratio = lastRatio_;

  if (src_process(state_, &data) != 0) {
    return false;
  }

  outputFramesWritten = static_cast<std::size_t>(data.output_frames_gen);
  for (std::size_t i = 0; i < outputFramesWritten; ++i) {
    outputChannels[0][i] = outputInterleaved_[i * 2 + 0];
    outputChannels[1][i] = outputInterleaved_[i * 2 + 1];
  }
  return outputFramesWritten > 0;
}

}  // namespace apm44
