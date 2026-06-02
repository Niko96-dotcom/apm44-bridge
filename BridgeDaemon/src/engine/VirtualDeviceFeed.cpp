#include "engine/VirtualDeviceFeed.h"

#include <algorithm>
#include <utility>

namespace apm44 {

VirtualDeviceFeed::VirtualDeviceFeed(std::string ringName) : ring_(std::move(ringName)) {}

bool VirtualDeviceFeed::open() {
  close();
  if (!ring_.open(ShmRingRole::Consumer)) {
    lastOpenErrorCode_ = ring_.lastErrorCode();
    lastOpenErrno_ = ring_.lastErrno();
    lastOpenError_ = ring_.lastError();
    return false;
  }
  lastOpenErrorCode_ = ShmRingErrorCode::None;
  lastOpenErrno_ = 0;
  lastOpenError_.clear();
  constexpr std::size_t kMaxDrain = 2048;
  interleavedScratch_.resize(PlanarRingBuffer::kChannels * kMaxDrain);
  planarScratch0_.resize(kMaxDrain);
  planarScratch1_.resize(kMaxDrain);
  ring_.setDaemonReady();
  return true;
}

void VirtualDeviceFeed::close() { ring_.close(); }

std::size_t VirtualDeviceFeed::drainTo(PlanarRingBuffer& ring, std::size_t maxFrames) {
  if (!ring_.isMapped() || maxFrames == 0) {
    return 0;
  }
  const std::size_t chunk =
      std::min({maxFrames, planarScratch0_.size(), interleavedScratch_.size() / PlanarRingBuffer::kChannels});
  const std::size_t popped = ring_.popInterleaved(interleavedScratch_.data(), chunk);
  if (popped == 0) {
    return 0;
  }
  for (std::size_t i = 0; i < popped; ++i) {
    planarScratch0_[i] = interleavedScratch_[i * 2 + 0];
    planarScratch1_[i] = interleavedScratch_[i * 2 + 1];
  }
  const float* channels[2] = {planarScratch0_.data(), planarScratch1_.data()};
  return ring.push(channels, popped);
}

}  // namespace apm44
