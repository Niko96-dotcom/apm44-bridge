#pragma once

#include <CoreAudio/CoreAudio.h>

#include <apm44/AudioFormats.h>

#include <string>

namespace apm44 {

struct AudioDeviceInfo {
  AudioDeviceID deviceId = kAudioObjectUnknown;
  std::string uid;
  std::string name;
  double nominalRate = 0.0;
  bool hasInput = false;
  bool hasOutput = false;
};

struct BridgeDevicePair {
  AudioDeviceInfo input;
  AudioDeviceInfo output;
  AudioStreamBasicDescription inputAsbd{};
  AudioStreamBasicDescription outputAsbd{};
};

}  // namespace apm44
