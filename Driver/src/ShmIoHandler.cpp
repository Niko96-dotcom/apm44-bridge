#include "ShmIoHandler.h"

#include <apm44/ShmRingLayout.h>

#include <algorithm>
#include <cstring>
#include <os/log.h>

namespace apm44 {

namespace {

os_log_t DriverLog() {
  static os_log_t log = os_log_create("com.niko.apm44.bridge", "HALDriver");
  return log;
}

}  // namespace

ShmIoHandler::ShmIoHandler() { ensureRingReady(); }

bool ShmIoHandler::ensureRingReady() {
  if (ring_.isMapped()) {
    return true;
  }
  if (!ring_.create(kDefaultShmCapacityFrames)) {
    os_log_error(DriverLog(), "APM44 shm ring create failed: %{public}s",
                 ring_.lastError().c_str());
    return false;
  }
  os_log(DriverLog(), "APM44 shm ring ready: %{public}s build=%{public}s", kShmRingName,
         kBuildId);
  convertScratch_.resize(kDefaultShmCapacityFrames * kShmChannels);
  return true;
}

OSStatus ShmIoHandler::OnStartIO() {
  if (!ensureRingReady()) {
    return kAudioHardwareUnspecifiedError;
  }
  ioRunning_ = true;
  return kAudioHardwareNoError;
}

void ShmIoHandler::OnStopIO() {
  ioRunning_ = false;
  // Keep shm mapped so apm44-bridge can stay connected across transport stop/start.
}

void ShmIoHandler::OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>&,
                                      Float64,
                                      Float64,
                                      const void* buff,
                                      UInt32 buffBytesSize) {
  if (buff == nullptr || buffBytesSize == 0 || !ring_.isMapped()) {
    return;
  }

  const UInt32 bytesPerFrame = sizeof(SInt16) * kShmChannels;
  if (buffBytesSize % bytesPerFrame != 0) {
    return;
  }
  const std::size_t frames = buffBytesSize / bytesPerFrame;
  if (frames > convertScratch_.size() / kShmChannels) {
    return;
  }

  const auto* samples = static_cast<const SInt16*>(buff);
  for (std::size_t i = 0; i < frames; ++i) {
    convertScratch_[i * 2 + 0] = static_cast<float>(samples[i * 2 + 0]) / 32768.0f;
    convertScratch_[i * 2 + 1] = static_cast<float>(samples[i * 2 + 1]) / 32768.0f;
  }

  const std::size_t pushed = ring_.pushInterleaved(convertScratch_.data(), frames);
  if (pushed < frames) {
    // Drop policy: bounded ring; oldest implicitly skipped when full (SPSC reserve slot).
  }
}

}  // namespace apm44
