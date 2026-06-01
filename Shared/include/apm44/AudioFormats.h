#pragma once

#include <CoreAudio/CoreAudio.h>

namespace apm44 {

inline constexpr double kInputSampleRate = 44100.0;
inline constexpr double kOutputSampleRate = 48000.0;

AudioStreamBasicDescription MakeFloat32StereoNonInterleaved(double sampleRate);

bool AsbdMatchesFloat32StereoNonInterleaved(const AudioStreamBasicDescription& asbd,
                                            double sampleRate,
                                            double rateTolerance = 1.0);

}  // namespace apm44
