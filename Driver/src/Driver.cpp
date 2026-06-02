#include "ShmIoHandler.h"
#include "DriverFormat.h"

#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>

namespace {

std::shared_ptr<aspl::Driver> CreateAPM44Driver() {
  auto context = std::make_shared<aspl::Context>();

  aspl::DeviceParameters deviceParams;
  deviceParams.Name = "APM44 Bridge";
  deviceParams.DeviceUID = "com.niko.apm44.bridge.device";
  deviceParams.ModelUID = "com.niko.apm44.bridge.model";
  deviceParams.SampleRate = apm44::kApm44DriverSampleRate;
  deviceParams.ChannelCount = apm44::kApm44DriverChannelCount;
  deviceParams.EnableMixing = true;

  auto device = std::make_shared<aspl::Device>(context, deviceParams);

  AudioValueRange rateOnly{};
  rateOnly.mMinimum = static_cast<Float64>(apm44::kApm44DriverSampleRate);
  rateOnly.mMaximum = static_cast<Float64>(apm44::kApm44DriverSampleRate);
  device->SetAvailableSampleRatesAsync({rateOnly});

  auto volumeControl = device->AddVolumeControlAsync(kAudioObjectPropertyScopeOutput);
  auto muteControl = device->AddMuteControlAsync(kAudioObjectPropertyScopeOutput);

  for (UInt32 channel = 1; channel <= apm44::kApm44DriverStreamCount; ++channel) {
    auto stream = std::make_shared<apm44::Apm44OutputStream>(context, device, channel);
    device->AddStreamAsync(stream);
    stream->AttachVolumeControl(volumeControl);
    stream->AttachMuteControl(muteControl);
  }

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
