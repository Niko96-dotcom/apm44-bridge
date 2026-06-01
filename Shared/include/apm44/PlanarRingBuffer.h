#pragma once

#include <atomic>
#include <cstddef>
#include <vector>

namespace apm44 {

// Lock-free single-producer single-consumer planar float ring (2 channels).
// Tracks fill at the 44.1 kHz input-rate domain. No allocation after prepare().
class PlanarRingBuffer {
 public:
  static constexpr std::size_t kChannels = 2;

  PlanarRingBuffer() = default;

  void prepare(std::size_t requestedFrames);
  std::size_t capacityFrames() const { return capacityFrames_; }

  std::size_t push(const float* const channelData[kChannels], std::size_t frameCount);
  std::size_t pop(float* const channelData[kChannels], std::size_t frameCount);

  std::size_t availableToRead() const;
  std::size_t availableToWrite() const;
  std::size_t fillFrames() const { return availableToRead(); }
  double fillMs(double sampleRate) const;
  static std::size_t framesForMilliseconds(double ms, double sampleRate);

  void reset();

 private:
  static std::size_t NextPowerOfTwo(std::size_t value);

  std::size_t capacityFrames_ = 0;
  std::size_t indexMask_ = 0;
  std::vector<float> storage_;
  std::atomic<std::size_t> writeIndex_{0};
  std::atomic<std::size_t> readIndex_{0};
};

}  // namespace apm44
