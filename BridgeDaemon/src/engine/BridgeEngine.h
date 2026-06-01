#pragma once

#include "engine/AudioConverterSrc.h"
#include "hal/HalTypes.h"

#include <apm44/PlanarRingBuffer.h>

#include <atomic>
#include <cstdint>
#include <vector>

namespace apm44 {

class BridgeEngine {
 public:
  bool prepare(const BridgeDevicePair& devices);
  bool start();
  void stop();
  void runUntilSignal();

  const BridgeDevicePair& devices() const { return devices_; }
  std::size_t ringCapacity() const { return ring_.capacityFrames(); }
  double converterRatio() const { return converter_.nominalRatio(); }
  uint64_t xrunCount() const { return xruns_.load(std::memory_order_relaxed); }

  // Called from IOProcs (RT-safe).
  void onInput(const float* const channels[2], std::size_t frames);
  void onOutput(float* const channels[2], std::size_t frames);

 private:
  BridgeDevicePair devices_{};
  PlanarRingBuffer ring_;
  AudioConverterSrc converter_;

  std::vector<float> channel0Scratch_;
  std::vector<float> channel1Scratch_;
  std::vector<float> convertOut0_;
  std::vector<float> convertOut1_;

  std::atomic<uint64_t> xruns_{0};
  bool running_ = false;

  AudioDeviceIOProcID inputProc_ = nullptr;
  AudioDeviceIOProcID outputProc_ = nullptr;
};

}  // namespace apm44
