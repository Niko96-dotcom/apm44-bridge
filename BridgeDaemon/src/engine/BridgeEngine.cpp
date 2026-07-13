#include "engine/BridgeEngine.h"

#include "engine/BridgeControlLoop.h"
#include "engine/BridgeInputOverrun.h"
#include "engine/IoProcHandlers.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <chrono>
#include <csignal>
#include <thread>
#include <cstring>
#include <iostream>
#include <vector>

namespace apm44 {

namespace {

volatile std::sig_atomic_t gStopRequested = 0;
constexpr double kVirtualDeviceMaxPpm = 3000.0;

void SignalHandler(int) { gStopRequested = 1; }

bool TrySetBufferFrameSize(AudioDeviceID deviceId, UInt32 frames) {
  AudioObjectPropertyAddress address{kAudioDevicePropertyBufferFrameSize,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
  return AudioObjectSetPropertyData(deviceId, &address, 0, nullptr, sizeof(frames), &frames) ==
         noErr;
}

UInt32 ReadBufferFrameSize(AudioDeviceID deviceId) {
  AudioObjectPropertyAddress address{kAudioDevicePropertyBufferFrameSize,
                                     kAudioObjectPropertyScopeGlobal,
                                     kAudioObjectPropertyElementMain};
  UInt32 frames = 0;
  UInt32 size = sizeof(frames);
  if (AudioObjectGetPropertyData(deviceId, &address, 0, nullptr, &size, &frames) != noErr) {
    return 0;
  }
  return frames;
}

std::size_t MaxInputFramesForOutputFrames(std::size_t outputFrames) {
  return static_cast<std::size_t>(std::ceil(static_cast<double>(outputFrames) *
                                            kInputSampleRate / kOutputSampleRate));
}

void HoldLastSample(float* ch0, float* ch1, std::size_t converted, std::size_t frames) {
  if (converted == 0 || converted >= frames) {
    return;
  }
  const float l = ch0[converted - 1];
  const float r = ch1[converted - 1];
  for (std::size_t i = converted; i < frames; ++i) {
    ch0[i] = l;
    ch1[i] = r;
  }
}

bool IsFatalShmOpenFailure(ShmRingErrorCode code, int err) {
  if (code == ShmRingErrorCode::InvalidHeader || code == ShmRingErrorCode::PermissionFailed ||
      code == ShmRingErrorCode::ConsumerBusy) {
    return true;
  }
  if ((code == ShmRingErrorCode::OpenFailed || code == ShmRingErrorCode::MapFailed) &&
      (err == EACCES || err == EPERM)) {
    return true;
  }
  return false;
}

}  // namespace

bool BridgeEngine::prepare(const BridgeDevicePair& devices, const BridgeEngineOptions& options) {
  devices_ = devices;
  options_ = options;
  virtualDevice_ = options.virtualDevice;

  if (virtualDevice_) {
    constexpr auto kPollInterval = std::chrono::milliseconds(100);
    constexpr auto kWaitTimeout = std::chrono::seconds(15);
    const auto deadline = std::chrono::steady_clock::now() + kWaitTimeout;
    bool printedWaitHint = false;
    while (!virtualFeed_.open()) {
      if (!printedWaitHint) {
        std::cerr << "Waiting for APM44 Bridge shm: the HAL driver should create "
                  << kShmRingName
                  << " when APM44 Bridge is loaded. If this persists, reinstall the matching "
                     "driver, reload Core Audio, or run scripts/verify-hal-driver.sh.\n";
        printedWaitHint = true;
      }
      if (IsFatalShmOpenFailure(virtualFeed_.lastOpenErrorCode(), virtualFeed_.lastOpenErrno())) {
        std::cerr << "error: APM44 Bridge shm open failed: "
                  << virtualFeed_.lastOpenError() << "\n";
        return false;
      }
      if (std::chrono::steady_clock::now() >= deadline) {
        std::cerr << "error: could not open shm ring after "
                  << std::chrono::duration_cast<std::chrono::seconds>(kWaitTimeout).count()
                  << "s";
        if (!virtualFeed_.lastOpenError().empty()) {
          std::cerr << ": " << virtualFeed_.lastOpenError();
        }
        std::cerr << "\n";
        return false;
      }
      std::this_thread::sleep_for(kPollInterval);
    }
    if (printedWaitHint) {
      std::cerr << "Connected to APM44 Bridge shared-memory ring.\n";
    }
  }

  const double targetFillMs =
      virtualDevice_ ? std::max(options_.targetFillMs, 20.0) : options_.targetFillMs;
  targetFillFrames_ =
      PlanarRingBuffer::framesForMilliseconds(targetFillMs, kInputSampleRate);
  const std::size_t ringRequest = std::max(targetFillFrames_ * 2 + 512, std::size_t{1024});
  ring_.prepare(ringRequest);
  drift_.reset();
  drift_.setTargetFillFrames(targetFillFrames_);
  drift_.setMaxPpm(virtualDevice_ ? kVirtualDeviceMaxPpm : DriftController::kMaxPpm);
  inputOverruns_.store(0, std::memory_order_relaxed);
  inputFramesProcessed_.store(0, std::memory_order_relaxed);
  outputFramesProcessed_.store(0, std::memory_order_relaxed);
  inputDemand_.reset();
  virtualPrebuffer_.reset(targetFillFrames_);

  if (!virtualDevice_) {
    std::vector<float> prefill0(targetFillFrames_, 0.0f);
    std::vector<float> prefill1(targetFillFrames_, 0.0f);
    const float* preCh[2] = {prefill0.data(), prefill1.data()};
    ring_.push(preCh, targetFillFrames_);
  }

  if (!src_.prepare(options_.srcQuality)) {
    return false;
  }

  outputScratch0_.resize(kMaxCallbackFrames);
  outputScratch1_.resize(kMaxCallbackFrames);
  inputScratch0_.resize(kMaxCallbackFrames);
  inputScratch1_.resize(kMaxCallbackFrames);
  if (virtualDevice_) {
    virtualFeed_.markReady();
  }
  return true;
}

bool BridgeEngine::resetVirtualStreamEpoch() {
  ring_.reset();
  drift_.reset();
  drift_.setTargetFillFrames(targetFillFrames_);
  drift_.setMaxPpm(kVirtualDeviceMaxPpm);
  inputDemand_.reset();
  virtualPrebuffer_.reset(targetFillFrames_);
  return src_.reset();
}

double BridgeEngine::converterRatio() const {
  return src_.nominalRatio();
}

void BridgeEngine::onInput(const float* const channels[2], std::size_t frames) {
  inputFramesProcessed_.fetch_add(frames, std::memory_order_relaxed);
  if (PushDroppingNewInput(ring_, channels, frames)) {
    inputOverruns_.fetch_add(1, std::memory_order_relaxed);
  }
}

void BridgeEngine::publishMetricsSnapshot() {
  MetricsSnapshot next;
  next.fillMs = ring_.fillMs(kInputSampleRate);
  next.smoothedRatio = drift_.smoothedRatio();
  next.ppm = drift_.currentPpm();
  next.underruns = drift_.underrunCount();
  next.overruns = inputOverruns_.load(std::memory_order_relaxed);
  next.xruns = xruns_.load(std::memory_order_relaxed);
  PublishMetrics(publisher_, next);
}

MetricsSnapshot BridgeEngine::readMetricsSnapshot() const {
  return ReadMetrics(publisher_);
}

void BridgeEngine::onOutput(float* const channels[2], std::size_t frames) {
  outputFramesProcessed_.fetch_add(frames, std::memory_order_relaxed);
  struct PublishGuard {
    BridgeEngine& engine;
    ~PublishGuard() { engine.publishMetricsSnapshot(); }
  } publishGuard{*this};

  std::memset(channels[0], 0, frames * sizeof(float));
  std::memset(channels[1], 0, frames * sizeof(float));

  if (virtualDevice_) {
    const std::size_t maxInputFrames = MaxInputFramesForOutputFrames(frames);
    virtualFeed_.drainTo(ring_, maxInputFrames + 256);
  }

  const std::size_t fill = ring_.fillFrames();
  if (virtualDevice_ && !virtualPrebuffer_.shouldOutput(fill)) {
    return;
  }

  float* popCh[2] = {outputScratch0_.data(), outputScratch1_.data()};
  const double ratio = drift_.update(fill);
  src_.setRatio(ratio);
  const std::size_t inputFramesNeeded = inputDemand_.consume(frames, ratio);
  const std::size_t maxPop = std::min(inputFramesNeeded, outputScratch0_.size());
  const std::size_t popped = ring_.pop(popCh, maxPop);
  if (popped == 0) {
    drift_.notifyUnderrun();
    if (virtualDevice_) {
      virtualPrebuffer_.forceRebuffer();
      inputDemand_.reset();
    }
    xruns_.fetch_add(1, std::memory_order_relaxed);
    return;
  }

  std::size_t converted = 0;
  const float* inCh[2] = {popCh[0], popCh[1]};
  if (!src_.process(inCh, popped, channels, frames, converted) || converted == 0) {
    std::memset(channels[0], 0, frames * sizeof(float));
    std::memset(channels[1], 0, frames * sizeof(float));
    drift_.notifyUnderrun();
    if (virtualDevice_) {
      virtualPrebuffer_.forceRebuffer();
      inputDemand_.reset();
    }
    xruns_.fetch_add(1, std::memory_order_relaxed);
    return;
  }

  if (converted < frames) {
    HoldLastSample(channels[0], channels[1], converted, frames);
  }
  if (popped < maxPop) {
    drift_.notifyUnderrun();
    if (virtualDevice_ &&
        virtualPrebuffer_.shouldRebufferForPartialShortage(maxPop, popped)) {
      virtualPrebuffer_.forceRebuffer();
      inputDemand_.reset();
    }
  }
}

bool BridgeEngine::start() {
  if (running_) {
    return true;
  }

  if (!virtualDevice_) {
    if (!TrySetBufferFrameSize(devices_.input.deviceId, 512)) {
      std::cerr << "note: could not set 512-frame input buffer; using device default\n";
    }
  }
  if (!TrySetBufferFrameSize(devices_.output.deviceId, 512)) {
    std::cerr << "note: could not set 512-frame output buffer; using device default\n";
  }

  const UInt32 inBuf =
      virtualDevice_ ? 0 : ReadBufferFrameSize(devices_.input.deviceId);
  const UInt32 outBuf = ReadBufferFrameSize(devices_.output.deviceId);
  if (virtualDevice_) {
    std::cerr << "apm44-bridge: input=APM44 Bridge (shm) virtual-device mode\n";
  } else {
    std::cerr << "apm44-bridge: input='" << devices_.input.name << "' uid=" << devices_.input.uid
              << " rate=" << devices_.input.nominalRate << " buffer_frames=" << inBuf << "\n";
  }
  std::cerr << "apm44-bridge: output='" << devices_.output.name << "' uid=" << devices_.output.uid
            << " rate=" << devices_.output.nominalRate << " buffer_frames=" << outBuf << "\n";
  const double loggedTargetMs =
      virtualDevice_ ? std::max(options_.targetFillMs, 20.0) : options_.targetFillMs;
  std::cerr << "apm44-bridge: ring_capacity=" << ring_.capacityFrames()
            << " target_fill_ms=" << loggedTargetMs
            << " converter_ratio=" << converterRatio() << "\n";

  OSStatus status = noErr;
  bool inputStarted = false;
  if (!virtualDevice_) {
    status = AudioDeviceCreateIOProcID(devices_.input.deviceId, InputIoProc, this, &inputProc_);
    if (status != noErr) {
      return false;
    }
  }
  status = AudioDeviceCreateIOProcID(devices_.output.deviceId, OutputIoProc, this, &outputProc_);
  if (status != noErr) {
    if (inputProc_ != nullptr) {
      AudioDeviceDestroyIOProcID(devices_.input.deviceId, inputProc_);
      inputProc_ = nullptr;
    }
    return false;
  }

  if (!virtualDevice_) {
    status = AudioDeviceStart(devices_.input.deviceId, inputProc_);
    if (status != noErr) {
      cleanupIOProcs(false, false);
      return false;
    }
    inputStarted = true;
  }
  status = AudioDeviceStart(devices_.output.deviceId, outputProc_);
  if (status != noErr) {
    cleanupIOProcs(inputStarted, false);
    return false;
  }

  running_ = true;
  return true;
}

void BridgeEngine::cleanupIOProcs(bool inputStarted, bool outputStarted) {
  if (outputProc_ != nullptr) {
    if (outputStarted) {
      AudioDeviceStop(devices_.output.deviceId, outputProc_);
    }
    AudioDeviceDestroyIOProcID(devices_.output.deviceId, outputProc_);
    outputProc_ = nullptr;
  }
  if (inputProc_ != nullptr) {
    if (inputStarted) {
      AudioDeviceStop(devices_.input.deviceId, inputProc_);
    }
    AudioDeviceDestroyIOProcID(devices_.input.deviceId, inputProc_);
    inputProc_ = nullptr;
  }
}

void BridgeEngine::stop() {
  cleanupIOProcs(inputProc_ != nullptr, outputProc_ != nullptr);
  if (virtualDevice_) {
    virtualFeed_.close();
  }
  running_ = false;
}

void BridgeEngine::requestStop() { gStopRequested = 1; }

BridgeEngine::VirtualFeedStaleAction BridgeEngine::pollVirtualFeedStaleRing() {
  if (!virtualDevice_ || !running_ || outputProc_ == nullptr) {
    return VirtualFeedStaleAction::None;
  }
  if (!virtualFeed_.isRingStale()) {
    return VirtualFeedStaleAction::None;
  }

  // Stop output IO before unmapping; onOutput may call drainTo on the audio thread.
  const OSStatus stopStatus = AudioDeviceStop(devices_.output.deviceId, outputProc_);
  if (stopStatus != noErr) {
    std::cerr << "error: AudioDeviceStop before shm remap failed: " << stopStatus << "\n";
    return VirtualFeedStaleAction::StopForExit;
  }

  const StaleRingPollResult pollResult = virtualFeed_.pollStaleRing();

  VirtualFeedStaleAction action = VirtualFeedStaleAction::None;
  switch (pollResult) {
    case StaleRingPollResult::Ok:
      action = VirtualFeedStaleAction::None;
      break;
    case StaleRingPollResult::Remapped:
      if (!resetVirtualStreamEpoch()) {
        std::cerr << "error: could not reset SRC for remapped shm stream epoch\n";
        action = VirtualFeedStaleAction::StopForExit;
      } else {
        virtualFeed_.markReady();
        action = VirtualFeedStaleAction::StopForRemap;
      }
      break;
    case StaleRingPollResult::MustExit:
      action = VirtualFeedStaleAction::StopForExit;
      break;
  }

  if (pollResult != StaleRingPollResult::MustExit) {
    const OSStatus startStatus = AudioDeviceStart(devices_.output.deviceId, outputProc_);
    if (startStatus != noErr) {
      std::cerr << "error: AudioDeviceStart after shm remap failed: " << startStatus << "\n";
      return VirtualFeedStaleAction::StopForExit;
    }
  }

  return action;
}

void BridgeEngine::runUntilSignal(const std::function<void(const BridgeEngine&)>& onTick) {
  std::signal(SIGINT, SignalHandler);
  std::signal(SIGTERM, SignalHandler);
  std::cerr << "apm44-bridge: running (Ctrl+C to stop)\n";
  while (gStopRequested == 0) {
    if (onTick) {
      onTick(*this);
    }
    std::this_thread::sleep_for(kControlLoopInterval);
  }
  stop();
  const MetricsSnapshot stopped = readMetricsSnapshot();
  std::cerr << "apm44-bridge: stopped. fill_ms=" << stopped.fillMs
            << " ratio=" << drift_.smoothedRatio() << " ppm=" << drift_.currentPpm()
            << " underruns=" << drift_.underrunCount() << " overruns=" << stopped.overruns
            << " xruns=" << stopped.xruns << "\n";
}

}  // namespace apm44
