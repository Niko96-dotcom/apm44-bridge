#include <catch2/catch_test_macros.hpp>

#include "hal/DeviceEnumerator.h"

TEST_CASE("MatchBlackHoleDefault finds BlackHole 2ch", "[device_enumerator]") {
  std::vector<apm44::AudioDeviceInfo> devices;
  apm44::AudioDeviceInfo bh;
  bh.name = "BlackHole 2ch";
  bh.uid = "BlackHole2ch_UID";
  bh.hasInput = true;
  devices.push_back(bh);

  const auto match = apm44::MatchBlackHoleDefault(devices);
  REQUIRE(match.has_value());
  REQUIRE(match->name == "BlackHole 2ch");
}

TEST_CASE("MatchAirPodsDefault prefers AirPods Max", "[device_enumerator]") {
  std::vector<apm44::AudioDeviceInfo> devices;
  apm44::AudioDeviceInfo generic;
  generic.name = "AirPods";
  generic.hasOutput = true;
  apm44::AudioDeviceInfo max;
  max.name = "AirPods Max";
  max.hasOutput = true;
  devices.push_back(generic);
  devices.push_back(max);

  const auto match = apm44::MatchAirPodsDefault(devices);
  REQUIRE(match.has_value());
  REQUIRE(match->name == "AirPods Max");
}

TEST_CASE("MatchBlackHoleDefault missing yields nullopt", "[device_enumerator]") {
  std::vector<apm44::AudioDeviceInfo> devices;
  apm44::AudioDeviceInfo other;
  other.name = "Built-in Output";
  other.hasInput = true;
  devices.push_back(other);

  const auto match = apm44::MatchBlackHoleDefault(devices);
  REQUIRE_FALSE(match.has_value());
}
