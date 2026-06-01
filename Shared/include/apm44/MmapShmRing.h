#pragma once

#include "apm44/ShmRingLayout.h"

#include <cstddef>

namespace apm44 {

enum class ShmRingRole { Producer, Consumer };

// Cross-process SPSC ring: interleaved float stereo in the mmap segment.
// No heap allocation after map(); RT-safe push/pop when used single-threaded per role.
class MmapShmRing {
 public:
  MmapShmRing() = default;
  ~MmapShmRing();

  MmapShmRing(const MmapShmRing&) = delete;
  MmapShmRing& operator=(const MmapShmRing&) = delete;

  bool create(uint32_t capacityFrames = kDefaultShmCapacityFrames);
  bool open(ShmRingRole role);
  void close();

  bool isMapped() const { return base_ != nullptr; }
  const ShmRingHeader* header() const { return header_; }
  ShmRingHeader* header() { return header_; }

  std::size_t pushInterleaved(const float* interleaved, std::size_t frameCount);
  std::size_t popInterleaved(float* interleaved, std::size_t frameCount);
  std::size_t popToPlanar(float* const channelData[2], std::size_t frameCount);

  void setDaemonReady();

 private:
  float* samples() const;
  std::size_t availableToWrite() const;
  std::size_t availableToRead() const;

  void* base_ = nullptr;
  std::size_t mappedSize_ = 0;
  ShmRingHeader* header_ = nullptr;
  ShmRingRole role_ = ShmRingRole::Consumer;
  int fd_ = -1;
};

}  // namespace apm44
