#include "apm44/AudioFormats.h"

#include <cmath>

namespace apm44 {

AudioStreamBasicDescription MakeFloat32StereoNonInterleaved(double sampleRate) {
  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags =
      kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
  asbd.mBytesPerPacket = sizeof(float);
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = sizeof(float);
  asbd.mChannelsPerFrame = 2;
  asbd.mBitsPerChannel = 32;
  return asbd;
}

bool AsbdMatchesFloat32StereoNonInterleaved(const AudioStreamBasicDescription& asbd,
                                            double sampleRate,
                                            double rateTolerance) {
  if (asbd.mFormatID != kAudioFormatLinearPCM) {
    return false;
  }
  const auto requiredFlags = static_cast<UInt32>(kAudioFormatFlagIsFloat |
                                                 kAudioFormatFlagIsNonInterleaved);
  if ((asbd.mFormatFlags & requiredFlags) != requiredFlags) {
    return false;
  }
  if (asbd.mChannelsPerFrame != 2 || asbd.mBitsPerChannel != 32) {
    return false;
  }
  return std::fabs(asbd.mSampleRate - sampleRate) <= rateTolerance;
}

}  // namespace apm44
