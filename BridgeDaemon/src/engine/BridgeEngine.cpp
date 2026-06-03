#include "engine/BridgeEngine.h"

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
  if (code == ShmRingErrorCode::InvalidHeader || code == ShmRingErrorCode::PermissionFailed) {
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
  useLegacyConverter_ = options.useLegacyConverter;
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
  const std::size_t targetFillFrames =
      PlanarRingBuffer::framesForMilliseconds(targetFillMs, kInputSampleRate);
  const std::size_t ringRequest = std::max(targetFillFrames * 2 + 512, std::size_t{1024});
  ring_.prepare(ringRequest);
  drift_.reset();
  drift_.setTargetFillFrames(targetFillFrames);
  drift_.setMaxPpm(virtualDevice_ ? kVirtualDeviceMaxPpm : DriftController::kMaxPpm);
  inputDemand_.reset();
  virtualPrebuffer_.reset(targetFillFrames);

  if (!virtualDevice_) {
    std::vector<float> prefill0(targetFillFrames, 0.0f);
    std::vector<float> prefill1(targetFillFrames, 0.0f);
    const float* preCh[2] = {prefill0.data(), prefill1.data()};
    ring_.push(preCh, targetFillFrames);
  }

  if (useLegacyConverter_) {
    if (!legacyConverter_.prepare(devices_.inputAsbd, devices_.outputAsbd)) {
      return false;
    }
  } else {
    if (!src_.prepare(options_.srcQuality)) {
      return false;
    }
  }

  constexpr std::size_t kMaxCallbackFrames = 1024;
  outputScratch0_.resize(kMaxCallbackFrames);
  outputScratch1_.resize(kMaxCallbackFrames);
  inputDropScratch0_.resize(kMaxCallbackFrames);
  inputDropScratch1_.resize(kMaxCallbackFrames);
  return true;
}

double BridgeEngine::converterRatio() const {
  if (useLegacyConverter_) {
    return legacyConverter_.nominalRatio();
  }
  return src_.nominalRatio();
}

void BridgeEngine::onInput(const float* const channels[2], std::size_t frames) {
  const std::size_t pushed = ring_.push(channels, frames);
  if (pushed < frames) {
    drift_.notifyOverrun();
    float* dropCh[2] = {inputDropScratch0_.data(), inputDropScratch1_.data()};
    const std::size_t toDrop = frames - pushed;
    ring_.pop(dropCh, toDrop);
    const float* remainder[2] = {channels[0] + pushed, channels[1] + pushed};
    ring_.push(remainder, frames - pushed);
  }
}

void BridgeEngine::onOutput(float* const channels[2], std::size_t frames) {
  std::memset(channels[0], 0, frames * sizeof(float));
  std::memset(channels[1], 0, frames * sizeof(float));

  if (virtualDevice_) {
    const std::size_t maxInputFrames = MaxInputFramesForOutputFrames(frames);
    virtualFeed_.drainTo(ring_, maxInputFrames + 256);
  }

  const std::size_t fill = ring_.fillFrames();
  lastFillMs_ = ring_.fillMs(kInputSampleRate);
  if (virtualDevice_ && !virtualPrebuffer_.shouldOutput(fill)) {
    return;
  }

  float* popCh[2] = {outputScratch0_.data(), outputScratch1_.data()};
  double ratio = DriftController::kNominalRatio;
  if (!useLegacyConverter_) {
    ratio = drift_.update(fill);
    src_.setRatio(ratio);
  }
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

  if (useLegacyConverter_) {
    std::size_t converted = 0;
    const float* inCh[2] = {popCh[0], popCh[1]};
    if (!legacyConverter_.convert(inCh, popped, channels, frames, converted) || converted == 0) {
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
            << " legacy_converter=" << (useLegacyConverter_ ? "yes" : "no")
            << " converter_ratio=" << converterRatio() << "\n";

  OSStatus status = noErr;
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
      stop();
      return false;
    }
  }
  status = AudioDeviceStart(devices_.output.deviceId, outputProc_);
  if (status != noErr) {
    AudioDeviceStop(devices_.input.deviceId, inputProc_);
    stop();
    return false;
  }

  running_ = true;
  return true;
}

void BridgeEngine::stop() {
  if (outputProc_ != nullptr) {
    AudioDeviceStop(devices_.output.deviceId, outputProc_);
    AudioDeviceDestroyIOProcID(devices_.output.deviceId, outputProc_);
    outputProc_ = nullptr;
  }
  if (inputProc_ != nullptr) {
    AudioDeviceStop(devices_.input.deviceId, inputProc_);
    AudioDeviceDestroyIOProcID(devices_.input.deviceId, inputProc_);
    inputProc_ = nullptr;
  }
  if (virtualDevice_) {
    virtualFeed_.close();
  }
  running_ = false;
}

void BridgeEngine::runUntilSignal(const std::function<void(const BridgeEngine&)>& onTick) {
  std::signal(SIGINT, SignalHandler);
  std::signal(SIGTERM, SignalHandler);
  std::cerr << "apm44-bridge: running (Ctrl+C to stop)\n";
  while (gStopRequested == 0) {
    if (onTick) {
      onTick(*this);
      std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
  }
  stop();
  std::cerr << "apm44-bridge: stopped. fill_ms=" << lastFillMs_
            << " ratio=" << drift_.smoothedRatio() << " ppm=" << drift_.currentPpm()
            << " underruns=" << drift_.underrunCount() << " overruns=" << drift_.overrunCount()
            << " xruns=" << xrunCount() << "\n";
}

}  // namespace apm44
