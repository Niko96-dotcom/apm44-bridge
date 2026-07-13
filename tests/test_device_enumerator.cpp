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
  generic.isAlive = true;
  generic.nominalRate = 48'000;
  generic.outputChannels = 2;
  generic.supports48000 = true;
  apm44::AudioDeviceInfo max;
  max.name = "AirPods Max";
  max.hasOutput = true;
  max.isAlive = true;
  max.nominalRate = 48'000;
  max.outputChannels = 2;
  max.supports48000 = true;
  devices.push_back(generic);
  devices.push_back(max);

  const auto match = apm44::MatchAirPodsDefault(devices);
  REQUIRE(match.has_value());
  REQUIRE(match->name == "AirPods Max");
}

TEST_CASE("MatchAirPodsDefault prefers compatible USB endpoint over Bluetooth",
          "[device_enumerator]") {
  apm44::AudioDeviceInfo bluetooth;
  bluetooth.name = "Niko's AirPods Max";
  bluetooth.hasOutput = true;
  bluetooth.isAlive = true;
  bluetooth.nominalRate = 48'000;
  bluetooth.outputChannels = 2;
  bluetooth.supports48000 = true;
  bluetooth.transportType = kAudioDeviceTransportTypeBluetooth;

  auto usb = bluetooth;
  usb.uid = "airpods-usb";
  usb.transportType = kAudioDeviceTransportTypeUSB;

  const auto match = apm44::MatchAirPodsDefault({bluetooth, usb});
  REQUIRE(match.has_value());
  REQUIRE(match->uid == "airpods-usb");
}

TEST_CASE("MatchAirPodsDefault rejects incompatible endpoint", "[device_enumerator]") {
  apm44::AudioDeviceInfo device;
  device.name = "AirPods Max";
  device.hasOutput = true;
  device.isAlive = true;
  device.nominalRate = 48'000;
  device.outputChannels = 2;
  device.supports48000 = false;

  REQUIRE_FALSE(apm44::MatchAirPodsDefault({device}).has_value());
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
