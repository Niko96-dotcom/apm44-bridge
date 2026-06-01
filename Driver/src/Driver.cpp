#include "ShmIoHandler.h"

#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>

namespace {

constexpr UInt32 kSampleRate = 44100;
constexpr UInt32 kChannelCount = 2;

std::shared_ptr<aspl::Driver> CreateAPM44Driver() {
  auto context = std::make_shared<aspl::Context>();

  aspl::DeviceParameters deviceParams;
  deviceParams.Name = "APM44 Bridge";
  deviceParams.DeviceUID = "com.niko.apm44.bridge.device";
  deviceParams.ModelUID = "com.niko.apm44.bridge.model";
  deviceParams.SampleRate = kSampleRate;
  deviceParams.ChannelCount = kChannelCount;
  deviceParams.EnableMixing = true;

  auto device = std::make_shared<aspl::Device>(context, deviceParams);

  AudioValueRange rateOnly{};
  rateOnly.mMinimum = static_cast<Float64>(kSampleRate);
  rateOnly.mMaximum = static_cast<Float64>(kSampleRate);
  device->SetAvailableSampleRatesAsync({rateOnly});

  aspl::StreamParameters streamParams;
  streamParams.Direction = aspl::Direction::Output;
  streamParams.Format.mSampleRate = kSampleRate;
  streamParams.Format.mChannelsPerFrame = kChannelCount;
  streamParams.Format.mBytesPerFrame = sizeof(SInt16) * kChannelCount;
  streamParams.Format.mFramesPerPacket = 1;
  streamParams.Format.mBytesPerPacket = streamParams.Format.mBytesPerFrame;
  streamParams.Format.mFormatID = kAudioFormatLinearPCM;
  streamParams.Format.mFormatFlags =
      kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;

  device->AddStreamWithControlsAsync(streamParams);

  auto handler = std::make_shared<apm44::ShmIoHandler>();
  device->SetControlHandler(std::static_pointer_cast<aspl::ControlRequestHandler>(handler));
  device->SetIOHandler(std::static_pointer_cast<aspl::IORequestHandler>(handler));

  auto plugin = std::make_shared<aspl::Plugin>(context);
  plugin->AddDevice(device);

  return std::make_shared<aspl::Driver>(context, plugin);
}

}  // namespace

extern "C" void* APM44EntryPoint(CFAllocatorRef, CFUUIDRef typeUUID) {
  if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
    return nullptr;
  }
  static std::shared_ptr<aspl::Driver> driver = CreateAPM44Driver();
  return driver->GetReference();
}
