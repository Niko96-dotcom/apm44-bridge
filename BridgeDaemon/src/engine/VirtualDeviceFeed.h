#pragma once

#include <apm44/MmapShmRing.h>
#include <apm44/PlanarRingBuffer.h>

#include <vector>

namespace apm44 {

class VirtualDeviceFeed {
 public:
  bool open();
  void close();
  bool isOpen() const { return ring_.isMapped(); }

  std::size_t drainTo(PlanarRingBuffer& ring, std::size_t maxFrames);

 private:
  MmapShmRing ring_;
  std::vector<float> interleavedScratch_;
  std::vector<float> planarScratch0_;
  std::vector<float> planarScratch1_;
};

}  // namespace apm44
