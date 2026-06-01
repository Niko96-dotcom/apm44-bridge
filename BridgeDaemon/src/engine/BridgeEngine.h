#pragma once

#include "engine/AudioConverterSrc.h"
#include "engine/LibSamplerateSrc.h"
#include "engine/VirtualDeviceFeed.h"
#include "hal/HalTypes.h"

#include <apm44/DriftController.h>
#include <apm44/PlanarRingBuffer.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <vector>

namespace apm44 {

struct BridgeEngineOptions {
  double targetFillMs = 15.0;
  LibSamplerateSrc::Quality srcQuality = LibSamplerateSrc::Quality::Medium;
  bool useLegacyConverter = false;
  bool virtualDevice = false;
};

class BridgeEngine {
 public:
  bool prepare(const BridgeDevicePair& devices, const BridgeEngineOptions& options = {});
  bool start();
  void stop();
  void runUntilSignal(const std::function<void(const BridgeEngine&)>& onTick = nullptr);

  const BridgeDevicePair& devices() const { return devices_; }
  std::size_t ringCapacity() const { return ring_.capacityFrames(); }
  double converterRatio() const;
  uint64_t xrunCount() const { return xruns_.load(std::memory_order_relaxed); }

  double lastFillMs() const { return lastFillMs_; }
  double lastSmoothedRatio() const { return drift_.smoothedRatio(); }
  double lastPpm() const { return drift_.currentPpm(); }
  uint64_t underrunCount() const { return drift_.underrunCount(); }
  uint64_t overrunCount() const { return drift_.overrunCount(); }

  // Called from IOProcs (RT-safe).
  void onInput(const float* const channels[2], std::size_t frames);
  void onOutput(float* const channels[2], std::size_t frames);

  // Scratch exposed for interleaved HAL buffer conversion (IOProc only).
  float* inputScratch0() { return inputDropScratch0_.data(); }
  float* inputScratch1() { return inputDropScratch1_.data(); }
  float* outputScratch0() { return outputScratch0_.data(); }
  float* outputScratch1() { return outputScratch1_.data(); }

 private:
  BridgeDevicePair devices_{};
  BridgeEngineOptions options_{};
  PlanarRingBuffer ring_;
  DriftController drift_;
  LibSamplerateSrc src_;
  AudioConverterSrc legacyConverter_;
  bool useLegacyConverter_ = false;

  std::vector<float> outputScratch0_;
  std::vector<float> outputScratch1_;
  std::vector<float> inputDropScratch0_;
  std::vector<float> inputDropScratch1_;

  std::atomic<uint64_t> xruns_{0};
  bool running_ = false;

  double lastFillMs_ = 0.0;

  AudioDeviceIOProcID inputProc_ = nullptr;
  AudioDeviceIOProcID outputProc_ = nullptr;

  VirtualDeviceFeed virtualFeed_;
  bool virtualDevice_ = false;
};

}  // namespace apm44
