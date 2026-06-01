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

TEST_CASE("AsbdMatchesFloat32Stereo interleaved USB AirPods shape", "[audio_formats]") {
  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = 48000.0;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  asbd.mBytesPerPacket = 8;
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = 8;
  asbd.mChannelsPerFrame = 2;
  asbd.mBitsPerChannel = 32;
  REQUIRE(apm44::AsbdMatchesFloat32Stereo(asbd, 48000.0));
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32StereoNonInterleaved(asbd, 48000.0));
}
