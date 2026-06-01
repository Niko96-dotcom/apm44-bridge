#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>

namespace apm44 {

inline constexpr const char* kShmRingName = "/apm44_bridge_ring";
inline constexpr uint32_t kShmMagic = 0x344D5041u;  // 'APM4' little-endian
inline constexpr uint32_t kShmVersion = 1u;
inline constexpr uint32_t kShmChannels = 2u;
inline constexpr uint32_t kDefaultShmCapacityFrames = 4096u;

struct ShmRingHeader {
  uint32_t magic = 0;
  uint32_t version = 0;
  uint32_t capacity_frames = 0;
  uint32_t sample_rate = 44100;
  uint32_t channels = kShmChannels;
  uint32_t reserved0 = 0;
  std::atomic<uint64_t> write_index{0};
  std::atomic<uint64_t> read_index{0};
  std::atomic<uint32_t> daemon_ready{0};
  std::atomic<uint32_t> driver_generation{0};
};

inline std::size_t ShmSamplesOffset() {
  constexpr std::size_t kAlignment = 64;
  return (sizeof(ShmRingHeader) + kAlignment - 1) & ~(kAlignment - 1);
}

inline std::size_t ShmTotalSize(uint32_t capacityFrames) {
  return ShmSamplesOffset() + static_cast<std::size_t>(capacityFrames) * kShmChannels *
                               sizeof(float);
}

inline bool ValidateShmHeader(const ShmRingHeader& header) {
  if (header.magic != kShmMagic || header.version != kShmVersion) {
    return false;
  }
  if (header.capacity_frames == 0 || header.channels != kShmChannels) {
    return false;
  }
  return true;
}

}  // namespace apm44
