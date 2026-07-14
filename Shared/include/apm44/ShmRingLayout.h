#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

namespace apm44 {

inline constexpr const char* kShmRingName = "/apm44_bridge_ring";
inline constexpr uint32_t kShmMagic = 0x344D5041u;  // 'APM4' little-endian
inline constexpr uint32_t kShmVersion = 4u;
inline constexpr uint32_t kShmSampleRate = 44100u;
inline constexpr uint32_t kShmChannels = 2u;
// The ring keeps one slot empty to distinguish full from empty. Core Audio can
// legally hand the HAL driver a 4096-frame callback, so a 4096-slot ring would
// necessarily discard one sample from every such callback. Keep enough room
// for a complete maximum-sized callback plus scheduling headroom.
inline constexpr uint32_t kDefaultShmCapacityFrames = 8192u;
inline constexpr std::size_t kShmBuildIdBytes = 64u;

#ifndef APM44_VERSION_STRING
#define APM44_VERSION_STRING "0.0.0-dev"
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
  std::atomic<uint64_t> producer_epoch{0};
  std::atomic<uint64_t> consumer_epoch{0};
  std::atomic<uint32_t> consumer_pid{0};
  std::atomic<uint32_t> reserved1{0};
  std::atomic<uint64_t> consumer_token{0};
  std::atomic<uint64_t> producer_overrun_events{0};
  std::atomic<uint64_t> producer_dropped_frames{0};
  std::atomic<uint64_t> producer_not_ready_dropped_frames{0};
  std::atomic<uint64_t> lane_queue_drops{0};
  std::atomic<uint64_t> lane_timestamp_mismatches{0};
  std::atomic<uint64_t> lane_frame_mismatch_dropped_frames{0};
  std::atomic<uint64_t> consumer_resets{0};
};

struct ShmProducerDiagnostics {
  uint64_t overrunEvents = 0;
  uint64_t droppedFrames = 0;
  uint64_t notReadyDroppedFrames = 0;
  uint64_t laneQueueDrops = 0;
  uint64_t laneTimestampMismatches = 0;
  uint64_t laneFrameMismatchDroppedFrames = 0;
  uint64_t consumerResets = 0;
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
