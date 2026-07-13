#include "ShmIoHandler.h"

#include <apm44/ShmRingLayout.h>

#include <algorithm>
#include <cmath>
#include <os/log.h>
#include <utility>

namespace apm44 {

namespace {

constexpr Float64 kLaneTimestampToleranceFrames = 128.0;
constexpr Float64 kSameTimestampToleranceFrames = 0.5;

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

bool ShmIoHandler::laneTimesMatch(const PendingLaneBlock& lhs,
                                  const PendingLaneBlock& rhs) {
  if (std::abs(lhs.zeroTimestamp - rhs.zeroTimestamp) < kSameTimestampToleranceFrames) {
    return std::abs(lhs.timestamp - rhs.timestamp) < kSameTimestampToleranceFrames;
  }
  return std::abs(lhs.logicalSampleTime - rhs.logicalSampleTime) <=
         kLaneTimestampToleranceFrames;
}

OSStatus ShmIoHandler::OnStartIO() {
  if (!ensureRingReady()) {
    return kAudioHardwareUnspecifiedError;
  }
  resetPendingLanes();
  ioRunning_.store(true, std::memory_order_release);
  return kAudioHardwareNoError;
}

void ShmIoHandler::OnStopIO() {
  ioRunning_.store(false, std::memory_order_release);
  // Keep shm mapped so apm44-bridge can stay connected across transport stop/start.
}

void ShmIoHandler::armFromRealtimeCallbackIfNeeded() {
  if (ioRunning_.load(std::memory_order_acquire)) {
    return;
  }
  resetPendingLanes();
  ioRunning_.store(true, std::memory_order_release);
}

void ShmIoHandler::OnProcessMixedOutput(const std::shared_ptr<aspl::Stream>& stream,
                                        Float64 zeroTimestamp,
                                        Float64 timestamp,
                                        Float32* frames,
                                        UInt32 frameCount,
                                        UInt32 channelCount) {
  if (frames == nullptr || frameCount == 0 || !ring_.isMapped()) {
    return;
  }
  armFromRealtimeCallbackIfNeeded();
  if (stream) {
    stream->ApplyProcessing(frames, frameCount, channelCount);
  }

  if (channelCount == kShmChannels) {
    pushInterleaved(frames, frameCount);
    return;
  }
  if (channelCount == 1) {
    pushMonoLane(stream, frames, frameCount, zeroTimestamp, timestamp);
    return;
  }
  recordProducerDrop(frameCount, false);
}

void ShmIoHandler::pushInterleaved(const Float32* frames, UInt32 frameCount) {
  if (!ring_.daemonReady()) {
    if (auto* header = ring_.header()) {
      header->producer_not_ready_dropped_frames.fetch_add(
          frameCount, std::memory_order_relaxed);
    }
    recordProducerDrop(frameCount, false);
    return;
  }
  const std::size_t pushed = ring_.pushInterleaved(frames, frameCount);
  if (pushed < frameCount) {
    recordProducerDrop(frameCount - pushed, true);
  }
}

void ShmIoHandler::recordProducerDrop(std::size_t frames, bool ringOverrun) {
  auto* header = ring_.header();
  if (header == nullptr || frames == 0) {
    return;
  }
  header->producer_dropped_frames.fetch_add(frames, std::memory_order_relaxed);
  if (ringOverrun) {
    header->producer_overrun_events.fetch_add(1, std::memory_order_relaxed);
  }
}

void ShmIoHandler::pushMonoLane(const std::shared_ptr<aspl::Stream>& stream,
                                const Float32* frames,
                                UInt32 frameCount,
                                Float64 zeroTimestamp,
                                Float64 timestamp) {
  if (!stream || frameCount > kDefaultShmCapacityFrames) {
    recordProducerDrop(frameCount, frameCount > kDefaultShmCapacityFrames);
    return;
  }

  const UInt32 startingChannel = stream->GetStartingChannel();
  if (startingChannel == 0 || startingChannel > kShmChannels) {
    recordProducerDrop(frameCount, false);
    return;
  }

  const UInt32 channelIndex = startingChannel - 1;
  enqueueLane(channelIndex, frames, frameCount, zeroTimestamp, timestamp);
  flushPendingLanes();
}

void ShmIoHandler::enqueueLane(UInt32 channelIndex,
                               const Float32* frames,
                               UInt32 frameCount,
                               Float64 zeroTimestamp,
                               Float64 timestamp) {
  if (pendingCount_[channelIndex] == kPendingLaneQueueDepth) {
    recordLaneDrop(channelIndex, LaneDropReason::QueueOverflow);
  }

  PendingLaneBlock& block = pendingLanes_[channelIndex][pendingWrite_[channelIndex]];
  block.zeroTimestamp = zeroTimestamp;
  block.timestamp = timestamp;
  block.logicalSampleTime = zeroTimestamp + timestamp;
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

void ShmIoHandler::recordLaneDrop(UInt32 channelIndex, LaneDropReason reason) {
  if (pendingCount_[channelIndex] == 0) {
    return;
  }
  const std::size_t droppedFrames = laneAt(channelIndex, 0).frameCount;
  if (auto* header = ring_.header()) {
    if (reason == LaneDropReason::QueueOverflow) {
      header->lane_queue_drops.fetch_add(1, std::memory_order_relaxed);
    } else {
      header->lane_timestamp_mismatches.fetch_add(1, std::memory_order_relaxed);
    }
  }
  recordProducerDrop(droppedFrames, false);
  dropLane(channelIndex);
}

int ShmIoHandler::findLaneMatchingBlock(UInt32 channelIndex,
                                        const PendingLaneBlock& block) const {
  for (std::size_t offset = 0; offset < pendingCount_[channelIndex]; ++offset) {
    const std::size_t index = (pendingRead_[channelIndex] + offset) % kPendingLaneQueueDepth;
    if (laneTimesMatch(pendingLanes_[channelIndex][index], block)) {
      return static_cast<int>(offset);
    }
  }
  return -1;
}

void ShmIoHandler::resetPendingLanes() noexcept {
  pendingRead_.fill(0);
  pendingWrite_.fill(0);
  pendingCount_.fill(0);
}

void ShmIoHandler::flushPendingLanes() {
  while (pendingCount_[0] > 0 && pendingCount_[1] > 0) {
    PendingLaneBlock& left = laneAt(0, 0);
    PendingLaneBlock& right = laneAt(1, 0);

    if (!laneTimesMatch(left, right)) {
      const int leftMatchForRight = findLaneMatchingBlock(0, right);
      if (leftMatchForRight > 0) {
        for (int i = 0; i < leftMatchForRight; ++i) {
          recordLaneDrop(0, LaneDropReason::TimestampMismatch);
        }
        continue;
      }
      const int rightMatchForLeft = findLaneMatchingBlock(1, left);
      if (rightMatchForLeft > 0) {
        for (int i = 0; i < rightMatchForLeft; ++i) {
          recordLaneDrop(1, LaneDropReason::TimestampMismatch);
        }
        continue;
      }
      if (left.logicalSampleTime <= right.logicalSampleTime) {
        recordLaneDrop(0, LaneDropReason::TimestampMismatch);
      } else {
        recordLaneDrop(1, LaneDropReason::TimestampMismatch);
      }
      continue;
    }

    pushLanePair(left, right);
    dropLane(0);
    dropLane(1);
  }
}

void ShmIoHandler::pushLanePair(const PendingLaneBlock& left,
                                const PendingLaneBlock& right) {
  const UInt32 frameCount = std::min(left.frameCount, right.frameCount);
  const UInt32 mismatchFrames =
      std::max(left.frameCount, right.frameCount) - frameCount;
  if (mismatchFrames > 0) {
    if (auto* header = ring_.header()) {
      header->lane_frame_mismatch_dropped_frames.fetch_add(
          mismatchFrames, std::memory_order_relaxed);
    }
    recordProducerDrop(mismatchFrames, false);
  }
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
