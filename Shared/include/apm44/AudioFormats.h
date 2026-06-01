#pragma once

#include <CoreAudio/CoreAudio.h>

namespace apm44 {

inline constexpr double kInputSampleRate = 44100.0;
inline constexpr double kOutputSampleRate = 48000.0;

AudioStreamBasicDescription MakeFloat32StereoNonInterleaved(double sampleRate);

bool AsbdMatchesFloat32StereoNonInterleaved(const AudioStreamBasicDescription& asbd,
                                            double sampleRate,
                                            double rateTolerance = 1.0);

// Accepts float32 stereo @ sampleRate (interleaved or non-interleaved). USB AirPods are
// typically interleaved; BlackHole and many HAL devices use non-interleaved.
bool AsbdMatchesFloat32Stereo(const AudioStreamBasicDescription& asbd,
                              double sampleRate,
                              double rateTolerance = 1.0);

inline bool AsbdIsNonInterleaved(const AudioStreamBasicDescription& asbd) {
  return (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
}

}  // namespace apm44
