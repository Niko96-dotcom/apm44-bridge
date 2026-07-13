#pragma once

#include "engine/LibSamplerateSrc.h"
#include "engine/MetricsPublisher.h"
#include "engine/VirtualPrebufferGate.h"
#include "engine/VirtualDeviceFeed.h"
#include "hal/HalTypes.h"

#include <apm44/MetricsSnapshot.h>

#include <apm44/DriftController.h>
#include <apm44/InputFrameDemand.h>
#include <apm44/PlanarRingBuffer.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <vector>

namespace apm44 {

struct BridgeEngineOptions {
  double targetFillMs = 15.0;
  LibSamplerateSrc::Quality srcQuality = LibSamplerateSrc::Quality::Medium;
  bool virtualDevice = false;
};

// MetricsSnapshot now lives in <apm44/MetricsSnapshot.h>; the typedef-
// like alias keeps the rest of the engine compiled unchanged.
using MetricsSnapshot = ::apm44::MetricsSnapshot;

class BridgeEngine {
 public:
  bool prepare(const BridgeDevicePair& devices, const BridgeEngineOptions& options = {});
  bool start();
  void stop();
  void runUntilSignal(const std::function<void(const BridgeEngine&)>& onTick = nullptr);
  static void requestStop();

  enum class VirtualFeedStaleAction { None, StopForRemap, StopForExit };
  VirtualFeedStaleAction pollVirtualFeedStaleRing();
  const std::string& virtualFeedLastOpenError() const {
    return virtualFeed_.lastOpenError();
  }

  const BridgeDevicePair& devices() const { return devices_; }
  std::size_t ringCapacity() const { return ring_.capacityFrames(); }
  double converterRatio() const;
  uint64_t xrunCount() const { return readMetricsSnapshot().xruns; }
  uint64_t inputFramesProcessed() const {
    return inputFramesProcessed_.load(std::memory_order_relaxed);
  }
  uint64_t outputFramesProcessed() const {
    return outputFramesProcessed_.load(std::memory_order_relaxed);
  }

  double lastFillMs() const { return readMetricsSnapshot().fillMs; }
  double lastSmoothedRatio() const { return readMetricsSnapshot().smoothedRatio; }
  double lastPpm() const { return readMetricsSnapshot().ppm; }
  uint64_t underrunCount() const { return readMetricsSnapshot().underruns; }
  uint64_t overrunCount() const { return readMetricsSnapshot().overruns; }

  // Called from IOProcs (RT-safe).
  void onInput(const float* const channels[2], std::size_t frames);
  void onOutput(float* const channels[2], std::size_t frames);

  // Scratch exposed for interleaved HAL buffer conversion (IOProc only).
  float* inputScratch0() { return inputScratch0_.data(); }
  float* inputScratch1() { return inputScratch1_.data(); }
  float* outputScratch0() { return outputScratch0_.data(); }
  float* outputScratch1() { return outputScratch1_.data(); }

 private:
  void cleanupIOProcs(bool inputStarted, bool outputStarted);
  bool resetVirtualStreamEpoch();
  void publishMetricsSnapshot();
  MetricsSnapshot readMetricsSnapshot() const;

  BridgeDevicePair devices_{};
  BridgeEngineOptions options_{};
  PlanarRingBuffer ring_;
  DriftController drift_;
  InputFrameDemand inputDemand_;
  VirtualPrebufferGate virtualPrebuffer_;
  LibSamplerateSrc src_;

  std::vector<float> outputScratch0_;
  std::vector<float> outputScratch1_;
  std::vector<float> inputScratch0_;
  std::vector<float> inputScratch1_;

  std::atomic<uint64_t> xruns_{0};
  std::atomic<uint64_t> inputOverruns_{0};
  std::atomic<uint64_t> inputFramesProcessed_{0};
  std::atomic<uint64_t> outputFramesProcessed_{0};
  bool running_ = false;

  // Seqlock state, extracted into MetricsPublisher so the contract
  // is independently testable. The legacy `metricsSeq_` /
  // `metricsSnapshot_` fields are now folded into `publisher_`.
  MetricsPublisherState publisher_;

  AudioDeviceIOProcID inputProc_ = nullptr;
  AudioDeviceIOProcID outputProc_ = nullptr;

  VirtualDeviceFeed virtualFeed_;
  bool virtualDevice_ = false;
  std::size_t targetFillFrames_ = 0;
};

}  // namespace apm44
