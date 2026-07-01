#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

namespace apm44 {

inline constexpr const char* kShmRingName = "/apm44_bridge_ring";
inline constexpr uint32_t kShmMagic = 0x344D5041u;  // 'APM4' little-endian
inline constexpr uint32_t kShmVersion = 2u;
inline constexpr uint32_t kShmSampleRate = 44100u;
inline constexpr uint32_t kShmChannels = 2u;
inline constexpr uint32_t kDefaultShmCapacityFrames = 4096u;
inline constexpr std::size_t kShmBuildIdBytes = 64u;

#ifndef APM44_VERSION_STRING
#define APM44_VERSION_STRING "0.11.1"
#endif

#ifndef APM44_BUILD_ID
#define APM44_BUILD_ID "unknown"
#endif

inline constexpr const char* kVersionString = APM44_VERSION_STRING;
inline constexpr const char* kBuildId = APM44_BUILD_ID;

struct ShmRingHeader {
  uint32_t magic = 0;
  uint32_t version = 0;
  uint32_t capacity_frames = 0;
  uint32_t sample_rate = kShmSampleRate;
  uint32_t channels = kShmChannels;
  uint32_t reserved0 = 0;
  uint32_t header_bytes = 0;
  uint32_t flags = 0;
  char producer_build_id[kShmBuildIdBytes] = {};
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

// Bounded rendering of a build-ID field. The on-wire field is a
// fixed-size `char[kShmBuildIdBytes]` that a buggy or hostile producer
// may leave without a NUL terminator — never stream it raw. `strnlen`
// reads at most `kShmBuildIdBytes` bytes (and stops early at the first
// NUL, so short C-strings like `kBuildId` are not over-read), then we
// copy exactly that many bytes. Returns "<unterminated>" when the field
// is empty or all-zero.
inline std::string RenderShmBuildId(const char* field) {
  if (field == nullptr) {
    return "<unterminated>";
  }
  const std::size_t len = ::strnlen(field, kShmBuildIdBytes);
  if (len == 0) {
    return "<unterminated>";
  }
  return std::string(field, len);
}

inline bool ValidateShmHeader(const ShmRingHeader& header) {
  if (header.magic != kShmMagic || header.version != kShmVersion) {
    return false;
  }
  if (header.header_bytes < sizeof(ShmRingHeader)) {
    return false;
  }
  if (header.capacity_frames == 0 || header.channels != kShmChannels) {
    return false;
  }
  if (header.sample_rate != kShmSampleRate) {
    return false;
  }
  if (RenderShmBuildId(header.producer_build_id) != RenderShmBuildId(kBuildId)) {
    return false;
  }
  return true;
}

}  // namespace apm44
