#pragma once

#include "apm44/ShmObjectIdentity.h"
#include "apm44/ShmRingLayout.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace apm44 {

enum class ShmRingRole { Producer, Consumer };

enum class ShmRingErrorCode {
  None,
  OpenFailed,
  CreateFailed,
  PermissionFailed,
  TruncateFailed,
  StatFailed,
  EmptyObject,
  MapFailed,
  InvalidHeader,
};

// Cross-process SPSC ring: interleaved float stereo in the mmap segment.
// No heap allocation after map(); RT-safe push/pop when used single-threaded per role.
class MmapShmRing {
 public:
  explicit MmapShmRing(std::string name = kShmRingName);
  ~MmapShmRing();

  MmapShmRing(const MmapShmRing&) = delete;
  MmapShmRing& operator=(const MmapShmRing&) = delete;

  bool create(uint32_t capacityFrames = kDefaultShmCapacityFrames);
  bool open(ShmRingRole role);
  void close();

  bool isMapped() const { return base_ != nullptr; }
  const std::string& name() const { return name_; }
  ShmRingErrorCode lastErrorCode() const { return lastErrorCode_; }
  int lastErrno() const { return lastErrno_; }
  const std::string& lastError() const { return lastError_; }
  const ShmRingHeader* header() const { return header_; }
  ShmRingHeader* header() { return header_; }

  std::size_t pushInterleaved(const float* interleaved, std::size_t frameCount);
  std::size_t popInterleaved(float* interleaved, std::size_t frameCount);
  std::size_t popToPlanar(float* const channelData[2], std::size_t frameCount);

  void setDaemonReady();

  const ShmObjectIdentity& mappedObjectIdentity() const { return mappedIdentity_; }
  uint32_t mappedDriverGeneration() const { return mappedDriverGeneration_; }
  bool isMappedObjectStale() const;

 private:
  float* samples() const;
  std::size_t availableToWrite() const;
  std::size_t availableToRead() const;
  void clearError();
  void recordError(ShmRingErrorCode code, std::string message, int err = 0);
  void recordErrno(ShmRingErrorCode code, const char* operation, int err);

  void* base_ = nullptr;
  std::size_t mappedSize_ = 0;
  ShmRingHeader* header_ = nullptr;
  ShmRingRole role_ = ShmRingRole::Consumer;
  int fd_ = -1;
  std::string name_;
  ShmRingErrorCode lastErrorCode_ = ShmRingErrorCode::None;
  int lastErrno_ = 0;
  std::string lastError_;
  ShmObjectIdentity mappedIdentity_{};
  uint32_t mappedDriverGeneration_ = 0;
};

}  // namespace apm44
