#include "hal/DeviceEnumerator.h"

#include <CoreAudio/CoreAudio.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstring>
#include <thread>
#include <unordered_map>
#include <vector>

namespace apm44 {

namespace {

std::vector<AudioObjectID> GetObjectList(AudioObjectID object,
                                       AudioObjectPropertySelector selector) {
  AudioObjectPropertyAddress address{
      selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(object, &address, 0, nullptr, &size) != noErr) {
    return {};
  }
  std::vector<AudioObjectID> ids(size / sizeof(AudioObjectID));
  if (size == 0) return ids;
  if (AudioObjectGetPropertyData(object, &address, 0, nullptr, &size, ids.data()) != noErr) {
    return {};
  }
  ids.resize(size / sizeof(AudioObjectID));
  return ids;
}

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

bool SupportsNominalRate(AudioDeviceID deviceId, double wantedRate) {
  AudioObjectPropertyAddress address{kAudioDevicePropertyAvailableNominalSampleRates,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
  UInt32 dataSize = 0;
  if (AudioObjectGetPropertyDataSize(deviceId, &address, 0, nullptr, &dataSize) != noErr ||
      dataSize < sizeof(AudioValueRange)) {
    return false;
  }
  std::vector<AudioValueRange> ranges(dataSize / sizeof(AudioValueRange));
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &dataSize, ranges.data()) !=
      noErr) {
    return false;
  }
  return std::any_of(ranges.begin(), ranges.end(), [wantedRate](const auto& range) {
    return wantedRate >= range.mMinimum && wantedRate <= range.mMaximum;
  });
}

bool IsCompatibleMonitoringOutput(const AudioDeviceInfo& device) {
  return device.hasOutput && device.isAlive && device.outputChannels >= 2 &&
         device.supports48000 && std::abs(device.nominalRate - kOutputSampleRate) <= 1.0 &&
         (device.outputFormatId == 0 || device.outputFormatId == kAudioFormatLinearPCM) &&
         (device.outputFormatBits == 0 || device.outputFormatBits == 32);
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
  std::optional<AudioDeviceInfo> usbAirPodsMax;
  std::optional<AudioDeviceInfo> usbAirPods;
  std::optional<AudioDeviceInfo> compatibleAirPodsMax;
  std::optional<AudioDeviceInfo> compatibleAirPods;
  for (const auto& device : devices) {
    if (!IsCompatibleMonitoringOutput(device)) {
      continue;
    }
    const bool isMax = ContainsIgnoreCase(device.name, "AirPods Max");
    const bool isAirPods = isMax || ContainsIgnoreCase(device.name, "AirPods");
    if (!isAirPods) {
      continue;
    }
    if (device.transportType == kAudioDeviceTransportTypeUSB) {
      if (isMax) {
        usbAirPodsMax = device;
      } else {
        usbAirPods = device;
      }
    } else if (isMax) {
      compatibleAirPodsMax = device;
    } else {
      compatibleAirPods = device;
    }
  }
  if (usbAirPodsMax) return usbAirPodsMax;
  if (usbAirPods) return usbAirPods;
  if (compatibleAirPodsMax) return compatibleAirPodsMax;
  return compatibleAirPods;
}

std::vector<AudioDeviceInfo> DeviceEnumerator::listAll() {
  std::vector<AudioDeviceInfo> result;
  auto deviceIds = GetObjectList(kAudioObjectSystemObject, kAudioHardwarePropertyDevices);
  std::unordered_map<AudioDeviceID, AudioObjectID> inactiveBoxes;
  // USB AirPods can publish a live device inside an unacquired AudioBox while
  // omitting it from the system device list. Discovery must not activate it.
  for (const auto box : GetObjectList(kAudioObjectSystemObject, kAudioHardwarePropertyBoxList)) {
    if (GetUInt32Property(box, kAudioBoxPropertyAcquired) != 0 ||
        GetUInt32Property(box, kAudioBoxPropertyIsProtected) != 0) continue;
    for (const auto device : GetObjectList(box, kAudioBoxPropertyDeviceList)) {
      if (GetUInt32Property(device, kAudioDevicePropertyTransportType) !=
          kAudioDeviceTransportTypeUSB) continue;
      if (std::find(deviceIds.begin(), deviceIds.end(), device) != deviceIds.end()) continue;
      deviceIds.push_back(device);
      inactiveBoxes.emplace(device, box);
    }
  }

  for (AudioDeviceID deviceId : deviceIds) {
    AudioDeviceInfo info;
    info.deviceId = deviceId;
    if (const auto box = inactiveBoxes.find(deviceId); box != inactiveBoxes.end()) {
      info.inactiveBoxId = box->second;
    }
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
    info.supports48000 = SupportsNominalRate(deviceId, kOutputSampleRate);
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

OSStatus DeviceEnumerator::activateOutput(AudioDeviceInfo& output) {
  if (output.inactiveBoxId == kAudioObjectUnknown) return noErr;
  AudioObjectPropertyAddress address{
      kAudioBoxPropertyAcquired, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  const UInt32 acquired = 1;
  const auto status = AudioObjectSetPropertyData(
      output.inactiveBoxId, &address, 0, nullptr, sizeof(acquired), &acquired);
  if (status != noErr) return status;

  // Acquisition may publish the device asynchronously or replace its ID.
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
  do {
    if (auto refreshed = findOutputByUid(output.uid);
        refreshed && refreshed->inactiveBoxId == kAudioObjectUnknown) {
      output = *refreshed;
      return noErr;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  } while (std::chrono::steady_clock::now() < deadline);
  return kAudioHardwareNotReadyError;
}

}  // namespace apm44
