#pragma once

#include <AudioToolbox/AudioConverter.h>
#include <CoreAudio/CoreAudio.h>

#include <cstddef>
#include <vector>

namespace apm44 {

class AudioConverterSrc {
 public:
  AudioConverterSrc() = default;
  ~AudioConverterSrc();

  AudioConverterSrc(const AudioConverterSrc&) = delete;
  AudioConverterSrc& operator=(const AudioConverterSrc&) = delete;

  bool prepare(const AudioStreamBasicDescription& inputAsbd,
               const AudioStreamBasicDescription& outputAsbd);

  bool convert(const float* const inputChannels[2], std::size_t inputFrames,
               float* const outputChannels[2], std::size_t outputCapacity,
               std::size_t& outputFramesWritten);

  double nominalRatio() const { return nominalRatio_; }

 private:
  AudioConverterRef converter_ = nullptr;
  double nominalRatio_ = 48000.0 / 44100.0;
  std::vector<float> inputInterleaved_;
  std::vector<float> outputInterleaved_;
  std::vector<float*> inputChannelPtrs_{2, nullptr};
  std::vector<float*> outputChannelPtrs_{2, nullptr};
};

}  // namespace apm44
