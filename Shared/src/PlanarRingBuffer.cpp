#include "apm44/PlanarRingBuffer.h"

#include <algorithm>
#include <cstring>

namespace apm44 {

void PlanarRingBuffer::prepare(std::size_t capacityFrames) {
  capacityFrames_ = capacityFrames;
  storage_.assign(capacityFrames_ * kChannels, 0.0f);
  writeIndex_.store(0, std::memory_order_relaxed);
  readIndex_.store(0, std::memory_order_relaxed);
}

void PlanarRingBuffer::reset() {
  writeIndex_.store(0, std::memory_order_relaxed);
  readIndex_.store(0, std::memory_order_relaxed);
}

std::size_t PlanarRingBuffer::availableToRead() const {
  const std::size_t w = writeIndex_.load(std::memory_order_acquire);
  const std::size_t r = readIndex_.load(std::memory_order_acquire);
  if (w >= r) {
    return w - r;
  }
  return capacityFrames_ - r + w;
}

std::size_t PlanarRingBuffer::availableToWrite() const {
  if (capacityFrames_ == 0) {
    return 0;
  }
  return capacityFrames_ - availableToRead() - 1;
}

std::size_t PlanarRingBuffer::push(const float* const channelData[kChannels],
                                   std::size_t frameCount) {
  const std::size_t writable = availableToWrite();
  const std::size_t toWrite = std::min(frameCount, writable);
  if (toWrite == 0 || capacityFrames_ == 0) {
    return 0;
  }

  std::size_t w = writeIndex_.load(std::memory_order_relaxed);
  for (std::size_t i = 0; i < toWrite; ++i) {
    storage_[w * kChannels + 0] = channelData[0][i];
    storage_[w * kChannels + 1] = channelData[1][i];
    w = (w + 1) % capacityFrames_;
  }
  writeIndex_.store(w, std::memory_order_release);
  return toWrite;
}

std::size_t PlanarRingBuffer::pop(float* const channelData[kChannels], std::size_t frameCount) {
  const std::size_t readable = availableToRead();
  const std::size_t toRead = std::min(frameCount, readable);
  if (toRead == 0 || capacityFrames_ == 0) {
    return 0;
  }

  std::size_t r = readIndex_.load(std::memory_order_relaxed);
  for (std::size_t i = 0; i < toRead; ++i) {
    channelData[0][i] = storage_[r * kChannels + 0];
    channelData[1][i] = storage_[r * kChannels + 1];
    r = (r + 1) % capacityFrames_;
  }
  readIndex_.store(r, std::memory_order_release);
  return toRead;
}

}  // namespace apm44
