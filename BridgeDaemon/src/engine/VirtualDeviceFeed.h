#pragma once

#include <apm44/MmapShmRing.h>
#include <apm44/PlanarRingBuffer.h>

#include <string>
#include <vector>

namespace apm44 {

enum class StaleRingPollResult { Ok, Remapped, MustExit };

class VirtualDeviceFeed {
 public:
  explicit VirtualDeviceFeed(std::string ringName = kShmRingName);
  bool open();
  void markReady();
  void close();
  bool isOpen() const { return ring_.isMapped(); }
  ShmRingErrorCode lastOpenErrorCode() const { return lastOpenErrorCode_; }
  int lastOpenErrno() const { return lastOpenErrno_; }
  const std::string& lastOpenError() const { return lastOpenError_; }

  std::size_t drainTo(PlanarRingBuffer& ring, std::size_t maxFrames);
  bool isRingStale() const;
  StaleRingPollResult pollStaleRing();
  ShmProducerDiagnostics producerDiagnostics() const {
    return ring_.producerDiagnostics();
  }

 private:
  MmapShmRing ring_;
  ShmRingErrorCode lastOpenErrorCode_ = ShmRingErrorCode::None;
  int lastOpenErrno_ = 0;
  std::string lastOpenError_;
  std::vector<float> planarScratch0_;
  std::vector<float> planarScratch1_;
};

}  // namespace apm44
