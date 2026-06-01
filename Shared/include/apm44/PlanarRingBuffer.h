#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace apm44 {

// Lock-free single-producer single-consumer planar float ring (2 channels).
// No allocation after prepare().
class PlanarRingBuffer {
 public:
  static constexpr std::size_t kChannels = 2;

  PlanarRingBuffer() = default;

  void prepare(std::size_t capacityFrames);
  std::size_t capacityFrames() const { return capacityFrames_; }

  std::size_t push(const float* const channelData[kChannels], std::size_t frameCount);
  std::size_t pop(float* const channelData[kChannels], std::size_t frameCount);
  std::size_t availableToRead() const;
  std::size_t availableToWrite() const;
  void reset();

 private:
  std::size_t capacityFrames_ = 0;
  std::vector<float> storage_;
  std::atomic<std::size_t> writeIndex_{0};
  std::atomic<std::size_t> readIndex_{0};
};

}  // namespace apm44
