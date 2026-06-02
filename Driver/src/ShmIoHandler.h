#pragma once

#include <apm44/MmapShmRing.h>

#include <aspl/ControlRequestHandler.hpp>
#include <aspl/IORequestHandler.hpp>

#include <array>
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
  bool ensureRingReady();
  void pushInterleaved(const Float32* frames, UInt32 frameCount);
  void pushMonoLane(const std::shared_ptr<aspl::Stream>& stream,
                    const Float32* frames,
                    UInt32 frameCount);

  MmapShmRing ring_;
  std::array<float, kDefaultShmCapacityFrames * kShmChannels> pendingInterleaved_{};
  UInt32 pendingFrameCount_ = 0;
  UInt32 pendingChannelMask_ = 0;
  bool ioRunning_ = false;
};

}  // namespace apm44
