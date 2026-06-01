#include <catch2/catch_test_macros.hpp>

#include "apm44/AudioFormats.h"

TEST_CASE("MakeFloat32StereoNonInterleaved 44100", "[audio_formats]") {
  const auto asbd = apm44::MakeFloat32StereoNonInterleaved(44100.0);
  REQUIRE(asbd.mSampleRate == 44100.0);
  REQUIRE(asbd.mChannelsPerFrame == 2);
  REQUIRE(asbd.mBitsPerChannel == 32);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0);
}

TEST_CASE("MakeFloat32StereoNonInterleaved 48000", "[audio_formats]") {
  const auto asbd = apm44::MakeFloat32StereoNonInterleaved(48000.0);
  REQUIRE(asbd.mSampleRate == 48000.0);
  REQUIRE(asbd.mChannelsPerFrame == 2);
}
