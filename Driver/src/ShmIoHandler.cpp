#include "ShmIoHandler.h"

#include <apm44/ShmRingLayout.h>

#include <algorithm>
#include <cmath>
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
                                        Float64 timestamp,
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
    pushMonoLane(stream, frames, frameCount, timestamp);
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
                                UInt32 frameCount,
                                Float64 sampleTime) {
  if (!stream || frameCount > kDefaultShmCapacityFrames) {
    return;
  }

  const UInt32 startingChannel = stream->GetStartingChannel();
  if (startingChannel == 0 || startingChannel > kShmChannels) {
    return;
  }

  const UInt32 channelIndex = startingChannel - 1;
  enqueueLane(channelIndex, frames, frameCount, sampleTime);
  flushPendingLanes();
}

void ShmIoHandler::enqueueLane(UInt32 channelIndex,
                               const Float32* frames,
                               UInt32 frameCount,
                               Float64 sampleTime) {
  if (pendingCount_[channelIndex] == kPendingLaneQueueDepth) {
    dropLane(channelIndex);
  }

  PendingLaneBlock& block = pendingLanes_[channelIndex][pendingWrite_[channelIndex]];
  block.sampleTime = sampleTime;
  block.frameCount = frameCount;
  for (UInt32 frame = 0; frame < frameCount; ++frame) {
    block.frames[frame] = frames[frame];
  }
  pendingWrite_[channelIndex] = (pendingWrite_[channelIndex] + 1) % kPendingLaneQueueDepth;
  ++pendingCount_[channelIndex];
}

ShmIoHandler::PendingLaneBlock& ShmIoHandler::laneAt(UInt32 channelIndex,
                                                     std::size_t offset) {
  const std::size_t index = (pendingRead_[channelIndex] + offset) % kPendingLaneQueueDepth;
  return pendingLanes_[channelIndex][index];
}

void ShmIoHandler::dropLane(UInt32 channelIndex) {
  if (pendingCount_[channelIndex] == 0) {
    return;
  }
  pendingRead_[channelIndex] = (pendingRead_[channelIndex] + 1) % kPendingLaneQueueDepth;
  --pendingCount_[channelIndex];
}

int ShmIoHandler::findLaneWithSampleTime(UInt32 channelIndex, Float64 sampleTime) const {
  for (std::size_t offset = 0; offset < pendingCount_[channelIndex]; ++offset) {
    const std::size_t index = (pendingRead_[channelIndex] + offset) % kPendingLaneQueueDepth;
    if (std::abs(pendingLanes_[channelIndex][index].sampleTime - sampleTime) < 0.5) {
      return static_cast<int>(offset);
    }
  }
  return -1;
}

void ShmIoHandler::flushPendingLanes() {
  while (pendingCount_[0] > 0 && pendingCount_[1] > 0) {
    PendingLaneBlock& left = laneAt(0, 0);
    PendingLaneBlock& right = laneAt(1, 0);

    if (std::abs(left.sampleTime - right.sampleTime) >= 0.5) {
      const int leftMatchForRight = findLaneWithSampleTime(0, right.sampleTime);
      if (leftMatchForRight > 0) {
        for (int i = 0; i < leftMatchForRight; ++i) {
          dropLane(0);
        }
        continue;
      }
      const int rightMatchForLeft = findLaneWithSampleTime(1, left.sampleTime);
      if (rightMatchForLeft > 0) {
        for (int i = 0; i < rightMatchForLeft; ++i) {
          dropLane(1);
        }
        continue;
      }
    }

    pushLanePair(left, right);
    dropLane(0);
    dropLane(1);
  }
}

void ShmIoHandler::pushLanePair(const PendingLaneBlock& left,
                                const PendingLaneBlock& right) {
  const UInt32 frameCount = std::min(left.frameCount, right.frameCount);
  for (UInt32 frame = 0; frame < frameCount; ++frame) {
    pendingInterleaved_[frame * kShmChannels + 0] = left.frames[frame];
    pendingInterleaved_[frame * kShmChannels + 1] = right.frames[frame];
  }
  pushInterleaved(pendingInterleaved_.data(), frameCount);
}

void ShmIoHandler::OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>&,
                                      Float64,
                                      Float64,
                                      const void*,
                                      UInt32) {
  // libASPL's ProcessMix phase provides canonical interleaved Float32 before native conversion.
}

}  // namespace apm44
