#pragma once

#include <apm44/MmapShmRing.h>

#include <aspl/ControlRequestHandler.hpp>
#include <aspl/IORequestHandler.hpp>

#include <array>
#include <cstddef>
#include <memory>
#include <string>

namespace apm44 {

class ShmIoHandler : public aspl::ControlRequestHandler, public aspl::IORequestHandler {
 public:
  explicit ShmIoHandler(std::string ringName = kShmRingName);
  OSStatus OnStartIO() override;
  void OnStopIO() override;

  void OnProcessMixedOutput(const std::shared_ptr<aspl::Stream>& stream,
                            Float64 zeroTimestamp,
                            Float64 timestamp,
                            Float32* frames,
                            UInt32 frameCount,
                            UInt32 channelCount) override;

  void OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>& stream,
                          Float64 zeroTimestamp,
                          Float64 timestamp,
                          const void* buff,
                          UInt32 buffBytesSize) override;

 private:
  static constexpr std::size_t kPendingLaneQueueDepth = 8;

  struct PendingLaneBlock {
    std::array<float, kDefaultShmCapacityFrames> frames{};
    Float64 sampleTime = 0.0;
    UInt32 frameCount = 0;
  };

  bool ensureRingReady();
  void pushInterleaved(const Float32* frames, UInt32 frameCount);
  void pushMonoLane(const std::shared_ptr<aspl::Stream>& stream,
                    const Float32* frames,
                    UInt32 frameCount,
                    Float64 sampleTime);
  void enqueueLane(UInt32 channelIndex, const Float32* frames, UInt32 frameCount,
                   Float64 sampleTime);
  PendingLaneBlock& laneAt(UInt32 channelIndex, std::size_t offset);
  void dropLane(UInt32 channelIndex);
  int findLaneWithSampleTime(UInt32 channelIndex, Float64 sampleTime) const;
  void flushPendingLanes();
  void pushLanePair(const PendingLaneBlock& left, const PendingLaneBlock& right);

  MmapShmRing ring_;
  std::array<float, kDefaultShmCapacityFrames * kShmChannels> pendingInterleaved_{};
  std::array<std::array<PendingLaneBlock, kPendingLaneQueueDepth>, kShmChannels> pendingLanes_{};
  std::array<std::size_t, kShmChannels> pendingRead_{};
  std::array<std::size_t, kShmChannels> pendingWrite_{};
  std::array<std::size_t, kShmChannels> pendingCount_{};
  bool ioRunning_ = false;
};

}  // namespace apm44
