#pragma once

#include "hal/HalTypes.h"

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace apm44 {

std::optional<AudioDeviceInfo> MatchBlackHoleDefault(const std::vector<AudioDeviceInfo>& devices);
std::optional<AudioDeviceInfo> MatchAirPodsDefault(const std::vector<AudioDeviceInfo>& devices);

class DeviceEnumerator {
 public:
  std::vector<AudioDeviceInfo> listAll();
  std::optional<AudioDeviceInfo> findByUid(std::string_view uid);
  std::optional<AudioDeviceInfo> findOutputByUid(std::string_view uid);
  std::optional<AudioDeviceInfo> defaultInput();
  std::optional<AudioDeviceInfo> defaultOutput();

  std::optional<AudioDeviceInfo> resolveInput(const std::optional<std::string>& uidOverride);
  std::optional<AudioDeviceInfo> resolveOutput(const std::optional<std::string>& uidOverride);
  OSStatus activateOutput(AudioDeviceInfo& output);
};

}  // namespace apm44
