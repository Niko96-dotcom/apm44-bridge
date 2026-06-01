#include "apm44/PlanarRingBuffer.h"

#include <algorithm>
#include <cmath>

namespace apm44 {

namespace {

constexpr std::size_t kMinCapacityFrames = 2;

}  // namespace

std::size_t PlanarRingBuffer::NextPowerOfTwo(std::size_t value) {
  if (value <= 1) {
    return kMinCapacityFrames;
  }
  std::size_t power = 1;
  while (power < value) {
    power <<= 1;
  }
  return power;
}

void PlanarRingBuffer::prepare(std::size_t requestedFrames) {
  const std::size_t requested = std::max(requestedFrames, kMinCapacityFrames);
  capacityFrames_ = NextPowerOfTwo(requested);
  indexMask_ = capacityFrames_ - 1;
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
  return w - r;
}

std::size_t PlanarRingBuffer::availableToWrite() const {
  if (capacityFrames_ == 0) {
    return 0;
  }
  const std::size_t occupied = availableToRead();
  if (occupied >= capacityFrames_ - 1) {
    return 0;
  }
  return capacityFrames_ - occupied - 1;
}

double PlanarRingBuffer::fillMs(double sampleRate) const {
  if (sampleRate <= 0.0) {
    return 0.0;
  }
  return static_cast<double>(fillFrames()) * 1000.0 / sampleRate;
}

std::size_t PlanarRingBuffer::framesForMilliseconds(double ms, double sampleRate) {
  if (ms <= 0.0 || sampleRate <= 0.0) {
    return 0;
  }
  return static_cast<std::size_t>(std::lround(ms * sampleRate / 1000.0));
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
    const std::size_t idx = (w + i) & indexMask_;
    storage_[idx * kChannels + 0] = channelData[0][i];
    storage_[idx * kChannels + 1] = channelData[1][i];
  }
  writeIndex_.store(w + toWrite, std::memory_order_release);
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
    const std::size_t idx = (r + i) & indexMask_;
    channelData[0][i] = storage_[idx * kChannels + 0];
    channelData[1][i] = storage_[idx * kChannels + 1];
  }
  readIndex_.store(r + toRead, std::memory_order_release);
  return toRead;
}

}  // namespace apm44
