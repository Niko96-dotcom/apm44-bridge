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
  if (!AsbdMatchesFloat32Stereo(asbd, sampleRate, rateTolerance)) {
    return false;
  }
  return (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
}

bool AsbdMatchesFloat32Stereo(const AudioStreamBasicDescription& asbd,
                              double sampleRate,
                              double rateTolerance) {
  constexpr UInt32 kFloatBytes = sizeof(float);
  constexpr UInt32 kStereoFrameBytes = kFloatBytes * 2;

  if (asbd.mFormatID != kAudioFormatLinearPCM) {
    return false;
  }
  if ((asbd.mFormatFlags & kAudioFormatFlagIsFloat) == 0) {
    return false;
  }
  if (asbd.mChannelsPerFrame != 2 || asbd.mBitsPerChannel != 32) {
    return false;
  }
  if (asbd.mFramesPerPacket != 1) {
    return false;
  }
  if (std::fabs(asbd.mSampleRate - sampleRate) > rateTolerance) {
    return false;
  }

  if ((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0) {
    return asbd.mBytesPerPacket == kFloatBytes && asbd.mBytesPerFrame == kFloatBytes;
  }

  return (asbd.mFormatFlags & kAudioFormatFlagIsPacked) != 0 &&
         asbd.mBytesPerPacket == kStereoFrameBytes &&
         asbd.mBytesPerFrame == kStereoFrameBytes;
}

}  // namespace apm44
