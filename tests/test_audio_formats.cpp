#include <catch2/catch_test_macros.hpp>

#include "apm44/AudioFormats.h"
#include "apm44/DeviceBufferLease.h"

namespace {

AudioStreamBasicDescription MakeInterleavedStereo48k() {
  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = 48000.0;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  asbd.mBytesPerPacket = sizeof(float) * 2;
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = sizeof(float) * 2;
  asbd.mChannelsPerFrame = 2;
  asbd.mBitsPerChannel = 32;
  return asbd;
}

}  // namespace

TEST_CASE("Device buffer lease restores only the bridge-owned value",
          "[device_buffer][restore]") {
  apm44::DeviceBufferLease lease;
  lease.begin(256, 512);
  REQUIRE_FALSE(lease.shouldRestore(512));

  lease.markChanged();
  REQUIRE(lease.shouldRestore(512));
  REQUIRE_FALSE(lease.shouldRestore(1024));
  REQUIRE_FALSE(lease.shouldRestore(256));

  lease.reset();
  REQUIRE_FALSE(lease.shouldRestore(512));
}

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
  const auto asbd = MakeInterleavedStereo48k();
  REQUIRE(apm44::AsbdMatchesFloat32Stereo(asbd, 48000.0));
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32StereoNonInterleaved(asbd, 48000.0));
}

TEST_CASE("AsbdMatchesFloat32Stereo accepts non-interleaved bridge shape", "[audio_formats]") {
  const auto asbd = apm44::MakeFloat32StereoNonInterleaved(44100.0);
  REQUIRE(apm44::AsbdMatchesFloat32Stereo(asbd, 44100.0));
  REQUIRE(apm44::AsbdMatchesFloat32StereoNonInterleaved(asbd, 44100.0));
}

TEST_CASE("AsbdMatchesFloat32Stereo rejects unsupported packet and byte layouts",
          "[audio_formats]") {
  auto interleaved = MakeInterleavedStereo48k();

  auto wrongInterleavedPacketBytes = interleaved;
  wrongInterleavedPacketBytes.mBytesPerPacket = sizeof(float);
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32Stereo(wrongInterleavedPacketBytes, 48000.0));

  auto wrongInterleavedFrameBytes = interleaved;
  wrongInterleavedFrameBytes.mBytesPerFrame = sizeof(float);
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32Stereo(wrongInterleavedFrameBytes, 48000.0));

  auto unpackedInterleaved = interleaved;
  unpackedInterleaved.mFormatFlags = kAudioFormatFlagIsFloat;
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32Stereo(unpackedInterleaved, 48000.0));

  auto multiFramePacket = interleaved;
  multiFramePacket.mFramesPerPacket = 2;
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32Stereo(multiFramePacket, 48000.0));

  auto nonInterleaved = apm44::MakeFloat32StereoNonInterleaved(44100.0);
  auto wrongNonInterleavedPacketBytes = nonInterleaved;
  wrongNonInterleavedPacketBytes.mBytesPerPacket = sizeof(float) * 2;
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32Stereo(wrongNonInterleavedPacketBytes, 44100.0));

  auto wrongNonInterleavedFrameBytes = nonInterleaved;
  wrongNonInterleavedFrameBytes.mBytesPerFrame = sizeof(float) * 2;
  REQUIRE_FALSE(apm44::AsbdMatchesFloat32Stereo(wrongNonInterleavedFrameBytes, 44100.0));
}
