#include "ShmIoHandler.h"

#include <apm44/ShmRingLayout.h>

#include <os/log.h>
#include <utility>

namespace apm44 {

namespace {

os_log_t DriverLog() {
  static os_log_t log = os_log_create("com.niko.apm44.bridge", "HALDriver");
  return log;
}

}  // namespace

ShmIoHandler::ShmIoHandler(std::string ringName) : ring_(std::move(ringName)) {
  ensureRingReady();
}

bool ShmIoHandler::ensureRingReady() {
  if (ring_.isMapped()) {
    return true;
  }
  if (!ring_.create(kDefaultShmCapacityFrames)) {
    os_log_error(DriverLog(), "APM44 shm ring create failed: %{public}s",
                 ring_.lastError().c_str());
    return false;
  }
  os_log(DriverLog(), "APM44 shm ring ready: %{public}s build=%{public}s", ring_.name().c_str(),
         kBuildId);
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

void ShmIoHandler::OnProcessMixedOutput(const std::shared_ptr<aspl::Stream>& stream,
                                        Float64,
                                        Float64,
                                        Float32* frames,
                                        UInt32 frameCount,
                                        UInt32 channelCount) {
  if (frames == nullptr || frameCount == 0 || !ring_.isMapped()) {
    return;
  }
  if (stream) {
    stream->ApplyProcessing(frames, frameCount, channelCount);
  }

  if (channelCount == kShmChannels) {
    pushInterleaved(frames, frameCount);
    return;
  }
  if (channelCount == 1) {
    pushMonoLane(stream, frames, frameCount);
  }
}

void ShmIoHandler::pushInterleaved(const Float32* frames, UInt32 frameCount) {
  const std::size_t pushed = ring_.pushInterleaved(frames, frameCount);
  if (pushed < frameCount) {
    // Drop policy: bounded ring; oldest implicitly skipped when full (SPSC reserve slot).
  }
}

void ShmIoHandler::pushMonoLane(const std::shared_ptr<aspl::Stream>& stream,
                                const Float32* frames,
                                UInt32 frameCount) {
  if (!stream || frameCount > kDefaultShmCapacityFrames) {
    return;
  }

  const UInt32 startingChannel = stream->GetStartingChannel();
  if (startingChannel == 0 || startingChannel > kShmChannels) {
    return;
  }

  const UInt32 channelIndex = startingChannel - 1;
  const UInt32 channelBit = 1u << channelIndex;
  if (pendingFrameCount_ != frameCount || (pendingChannelMask_ & channelBit) != 0) {
    pendingFrameCount_ = frameCount;
    pendingChannelMask_ = 0;
  }

  for (UInt32 frame = 0; frame < frameCount; ++frame) {
    pendingInterleaved_[frame * kShmChannels + channelIndex] = frames[frame];
  }

  pendingChannelMask_ |= channelBit;
  if (pendingChannelMask_ == ((1u << kShmChannels) - 1u)) {
    pushInterleaved(pendingInterleaved_.data(), pendingFrameCount_);
    pendingChannelMask_ = 0;
  }
}

void ShmIoHandler::OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>&,
                                      Float64,
                                      Float64,
                                      const void*,
                                      UInt32) {
  // libASPL's ProcessMix phase provides canonical interleaved Float32 before native conversion.
}

}  // namespace apm44
