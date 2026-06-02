#pragma once

#include <apm44/AudioFormats.h>

#include <aspl/Stream.hpp>

#include <memory>
#include <utility>
#include <vector>

namespace apm44 {

inline constexpr UInt32 kApm44DriverSampleRate = 44100;
inline constexpr UInt32 kApm44DriverChannelCount = 2;
inline constexpr UInt32 kApm44DriverStreamCount = 2;

inline AudioStreamBasicDescription MakeApm44DriverStreamFormat() {
  return MakeFloat32StereoNonInterleaved(static_cast<double>(kApm44DriverSampleRate));
}

inline AudioStreamBasicDescription MakeApm44DriverMonoLaneFormat() {
  auto asbd = MakeApm44DriverStreamFormat();
  asbd.mChannelsPerFrame = 1;
  asbd.mBytesPerPacket = sizeof(float);
  asbd.mBytesPerFrame = sizeof(float);
  return asbd;
}

inline AudioStreamRangedDescription MakeApm44DriverStreamRangedDescription() {
  AudioStreamRangedDescription ranged{};
  ranged.mFormat = MakeApm44DriverStreamFormat();
  ranged.mSampleRateRange.mMinimum = static_cast<Float64>(kApm44DriverSampleRate);
  ranged.mSampleRateRange.mMaximum = static_cast<Float64>(kApm44DriverSampleRate);
  return ranged;
}

inline AudioStreamRangedDescription MakeApm44DriverMonoLaneRangedDescription() {
  AudioStreamRangedDescription ranged{};
  ranged.mFormat = MakeApm44DriverMonoLaneFormat();
  ranged.mSampleRateRange.mMinimum = static_cast<Float64>(kApm44DriverSampleRate);
  ranged.mSampleRateRange.mMaximum = static_cast<Float64>(kApm44DriverSampleRate);
  return ranged;
}

inline aspl::StreamParameters MakeApm44OutputStreamParameters(UInt32 startingChannel) {
  aspl::StreamParameters streamParams;
  streamParams.Direction = aspl::Direction::Output;
  streamParams.StartingChannel = startingChannel;
  streamParams.Format = MakeApm44DriverMonoLaneFormat();
  return streamParams;
}

class Apm44OutputStream final : public aspl::Stream {
 public:
  Apm44OutputStream(std::shared_ptr<const aspl::Context> context,
                    std::shared_ptr<aspl::Device> device,
                    UInt32 startingChannel)
      : aspl::Stream(std::move(context),
                     std::move(device),
                     MakeApm44OutputStreamParameters(startingChannel)) {}

  AudioStreamBasicDescription GetPhysicalFormat() const override {
    return MakeApm44DriverMonoLaneFormat();
  }

  AudioStreamBasicDescription GetVirtualFormat() const override {
    return MakeApm44DriverMonoLaneFormat();
  }

  std::vector<AudioStreamRangedDescription> GetAvailablePhysicalFormats() const override {
    return {MakeApm44DriverMonoLaneRangedDescription()};
  }

  std::vector<AudioStreamRangedDescription> GetAvailableVirtualFormats() const override {
    return {MakeApm44DriverMonoLaneRangedDescription()};
  }
};

}  // namespace apm44
