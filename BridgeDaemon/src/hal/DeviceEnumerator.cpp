#include "hal/DeviceEnumerator.h"

#include <CoreAudio/CoreAudio.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <vector>

namespace apm44 {

namespace {

std::string ToLower(std::string_view s) {
  std::string out(s);
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return out;
}

bool ContainsIgnoreCase(std::string_view haystack, std::string_view needle) {
  return ToLower(haystack).find(ToLower(needle)) != std::string::npos;
}

std::string_view TrimUid(std::string_view uid) {
  while (!uid.empty() && std::isspace(static_cast<unsigned char>(uid.front()))) {
    uid.remove_prefix(1);
  }
  while (!uid.empty() && std::isspace(static_cast<unsigned char>(uid.back()))) {
    uid.remove_suffix(1);
  }
  return uid;
}

OSStatus GetStringProperty(AudioObjectID objectId, AudioObjectPropertySelector selector,
                           std::string& out) {
  AudioObjectPropertyAddress address{
      selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  UInt32 dataSize = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(objectId, &address, 0, nullptr, &dataSize);
  if (status != noErr || dataSize == 0) {
    return status;
  }
  CFStringRef cfString = nullptr;
  status = AudioObjectGetPropertyData(objectId, &address, 0, nullptr, &dataSize, &cfString);
  if (status != noErr || cfString == nullptr) {
    return status;
  }
  char buffer[512];
  if (!CFStringGetCString(cfString, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
    CFRelease(cfString);
    return kAudioHardwareUnspecifiedError;
  }
  out.assign(buffer);
  CFRelease(cfString);
  return noErr;
}

double GetNominalRate(AudioDeviceID deviceId) {
  AudioObjectPropertyAddress address{kAudioDevicePropertyNominalSampleRate,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
  Float64 rate = 0.0;
  UInt32 size = sizeof(rate);
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &size, &rate) != noErr) {
    return 0.0;
  }
  return rate;
}

UInt32 ChannelCount(AudioDeviceID deviceId, AudioObjectPropertyScope scope) {
  AudioObjectPropertyAddress address{kAudioDevicePropertyStreamConfiguration, scope,
                                     kAudioObjectPropertyElementMain};
  UInt32 dataSize = 0;
  if (AudioObjectGetPropertyDataSize(deviceId, &address, 0, nullptr, &dataSize) != noErr) {
    return 0;
  }
  std::vector<char> buffer(dataSize);
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &dataSize, buffer.data()) !=
      noErr) {
    return 0;
  }
  const auto* list = reinterpret_cast<const AudioBufferList*>(buffer.data());
  UInt32 channels = 0;
  for (UInt32 i = 0; i < list->mNumberBuffers; ++i) {
    channels += list->mBuffers[i].mNumberChannels;
  }
  return channels;
}

UInt32 GetUInt32Property(AudioDeviceID deviceId, AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress address{selector, kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
  UInt32 value = 0;
  UInt32 size = sizeof(value);
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &size, &value) != noErr) {
    return 0;
  }
  return value;
}

AudioStreamBasicDescription GetOutputStreamFormat(AudioDeviceID deviceId) {
  AudioObjectPropertyAddress address{kAudioDevicePropertyStreamFormat,
                                     kAudioDevicePropertyScopeOutput,
                                     kAudioObjectPropertyElementMain};
  AudioStreamBasicDescription format{};
  UInt32 size = sizeof(format);
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &size, &format) != noErr) {
    return {};
  }
  return format;
}

}  // namespace

std::optional<AudioDeviceInfo> MatchBlackHoleDefault(const std::vector<AudioDeviceInfo>& devices) {
  for (const auto& device : devices) {
    if (!device.hasInput) {
      continue;
    }
    if (ContainsIgnoreCase(device.name, "BlackHole 2ch") ||
        ContainsIgnoreCase(device.name, "BlackHole")) {
      return device;
    }
  }
  return std::nullopt;
}

std::optional<AudioDeviceInfo> MatchAirPodsDefault(const std::vector<AudioDeviceInfo>& devices) {
  std::optional<AudioDeviceInfo> airPodsMax;
  std::optional<AudioDeviceInfo> airPodsGeneric;
  for (const auto& device : devices) {
    if (!device.hasOutput) {
      continue;
    }
    if (ContainsIgnoreCase(device.name, "AirPods Max")) {
      airPodsMax = device;
    } else if (ContainsIgnoreCase(device.name, "AirPods")) {
      airPodsGeneric = device;
    }
  }
  if (airPodsMax) {
    return airPodsMax;
  }
  return airPodsGeneric;
}

std::vector<AudioDeviceInfo> DeviceEnumerator::listAll() {
  std::vector<AudioDeviceInfo> result;
  AudioObjectPropertyAddress address{kAudioHardwarePropertyDevices,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
  UInt32 dataSize = 0;
  if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nullptr, &dataSize) !=
      noErr) {
    return result;
  }
  const UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
  std::vector<AudioDeviceID> deviceIds(deviceCount);
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &dataSize,
                                 deviceIds.data()) != noErr) {
    return result;
  }

  for (AudioDeviceID deviceId : deviceIds) {
    AudioDeviceInfo info;
    info.deviceId = deviceId;
    if (GetStringProperty(deviceId, kAudioDevicePropertyDeviceUID, info.uid) != noErr) {
      continue;
    }
    if (GetStringProperty(deviceId, kAudioObjectPropertyName, info.name) != noErr) {
      info.name = info.uid;
    }
    info.nominalRate = GetNominalRate(deviceId);
    info.hasInput = ChannelCount(deviceId, kAudioDevicePropertyScopeInput) > 0;
    info.outputChannels = ChannelCount(deviceId, kAudioDevicePropertyScopeOutput);
    info.hasOutput = info.outputChannels > 0;
    info.isAlive = GetUInt32Property(deviceId, kAudioDevicePropertyDeviceIsAlive) != 0;
    info.bufferFrameSize =
        GetUInt32Property(deviceId, kAudioDevicePropertyBufferFrameSize);
    info.transportType =
        GetUInt32Property(deviceId, kAudioDevicePropertyTransportType);
    const auto format = GetOutputStreamFormat(deviceId);
    info.outputFormatId = format.mFormatID;
    info.outputFormatBits = format.mBitsPerChannel;
    result.push_back(std::move(info));
  }
  return result;
}

std::optional<AudioDeviceInfo> DeviceEnumerator::findByUid(std::string_view uid) {
  const std::string_view needle = TrimUid(uid);
  if (needle.empty()) {
    return std::nullopt;
  }
  for (const auto& device : listAll()) {
    if (TrimUid(device.uid) == needle) {
      return device;
    }
  }
  return std::nullopt;
}

std::optional<AudioDeviceInfo> DeviceEnumerator::findOutputByUid(std::string_view uid) {
  const std::string_view needle = TrimUid(uid);
  if (needle.empty()) {
    return std::nullopt;
  }
  if (auto exact = findByUid(needle)) {
    if (exact->hasOutput) {
      return exact;
    }
  }
  // Allow base UID without ":output" suffix (common when copying from AMS).
  if (needle.find(':') == std::string_view::npos) {
    const std::string suffix = std::string(needle) + ":output";
    if (auto withSuffix = findByUid(suffix)) {
      return withSuffix;
    }
  }
  return std::nullopt;
}

std::optional<AudioDeviceInfo> DeviceEnumerator::defaultInput() {
  return MatchBlackHoleDefault(listAll());
}

std::optional<AudioDeviceInfo> DeviceEnumerator::defaultOutput() {
  return MatchAirPodsDefault(listAll());
}

std::optional<AudioDeviceInfo> DeviceEnumerator::resolveInput(
    const std::optional<std::string>& uidOverride) {
  if (uidOverride) {
    return findByUid(*uidOverride);
  }
  return defaultInput();
}

std::optional<AudioDeviceInfo> DeviceEnumerator::resolveOutput(
    const std::optional<std::string>& uidOverride) {
  if (uidOverride) {
    return findOutputByUid(*uidOverride);
  }
  return defaultOutput();
}

}  // namespace apm44
