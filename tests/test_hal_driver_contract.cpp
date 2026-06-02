#include <catch2/catch_test_macros.hpp>

#include "DriverFormat.h"

#include <aspl/Device.hpp>

#include <memory>

namespace {

void RequireFloat32MonoLane44100(const AudioStreamBasicDescription& asbd) {
  REQUIRE(asbd.mSampleRate == 44100.0);
  REQUIRE(asbd.mFormatID == kAudioFormatLinearPCM);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) == 0);
  REQUIRE(asbd.mBytesPerPacket == sizeof(float));
  REQUIRE(asbd.mFramesPerPacket == 1);
  REQUIRE(asbd.mBytesPerFrame == sizeof(float));
  REQUIRE(asbd.mChannelsPerFrame == 1);
  REQUIRE(asbd.mBitsPerChannel == 32);
}

}  // namespace

TEST_CASE("APM44 logical driver format is Float32 non-interleaved 44100 stereo",
          "[hal_driver_contract]") {
  const auto asbd = apm44::MakeApm44DriverStreamFormat();

  REQUIRE(asbd.mSampleRate == 44100.0);
  REQUIRE(asbd.mFormatID == kAudioFormatLinearPCM);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0);
  REQUIRE((asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) == 0);
  REQUIRE(asbd.mBytesPerPacket == sizeof(float));
  REQUIRE(asbd.mFramesPerPacket == 1);
  REQUIRE(asbd.mBytesPerFrame == sizeof(float));
  REQUIRE(asbd.mChannelsPerFrame == 2);
  REQUIRE(asbd.mBitsPerChannel == 32);
}

TEST_CASE("APM44 HAL output streams are two mono lanes for non-interleaved stereo",
          "[hal_driver_contract]") {
  REQUIRE(apm44::kApm44DriverStreamCount == apm44::kApm44DriverChannelCount);

  for (UInt32 channel = 1; channel <= apm44::kApm44DriverStreamCount; ++channel) {
    const auto streamParams = apm44::MakeApm44OutputStreamParameters(channel);

    REQUIRE(streamParams.Direction == aspl::Direction::Output);
    REQUIRE(streamParams.StartingChannel == channel);
    RequireFloat32MonoLane44100(streamParams.Format);
  }
}

TEST_CASE("APM44 driver stream ranged format is 44100 only", "[hal_driver_contract]") {
  const auto ranged = apm44::MakeApm44DriverStreamRangedDescription();

  REQUIRE(ranged.mSampleRateRange.mMinimum == 44100.0);
  REQUIRE(ranged.mSampleRateRange.mMaximum == 44100.0);
  REQUIRE(apm44::AsbdMatchesFloat32StereoNonInterleaved(ranged.mFormat, 44100.0, 0.0));
}

TEST_CASE("APM44 output stream hard-pins virtual format to non-interleaved",
          "[hal_driver_contract]") {
  auto context = std::make_shared<aspl::Context>();
  aspl::DeviceParameters deviceParams;
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  auto device = std::make_shared<aspl::Device>(context, deviceParams);
  auto stream = std::make_shared<apm44::Apm44OutputStream>(context, device, 2);

  REQUIRE(stream->GetStartingChannel() == 2);
  RequireFloat32MonoLane44100(stream->GetPhysicalFormat());
  RequireFloat32MonoLane44100(stream->GetVirtualFormat());
  REQUIRE(stream->GetAvailablePhysicalFormats().size() == 1);
  REQUIRE(stream->GetAvailableVirtualFormats().size() == 1);
  RequireFloat32MonoLane44100(stream->GetAvailableVirtualFormats().front().mFormat);

  auto packed = apm44::MakeApm44DriverMonoLaneFormat();
  packed.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved;
  REQUIRE(stream->SetVirtualFormatAsync(packed) == kAudioDeviceUnsupportedFormatError);
}
