#pragma once

#include <apm44/DriftController.h>
#include <apm44/PlanarRingBuffer.h>

namespace apm44 {

// Producer-side drop-oldest when the planar ring cannot accept a full push.
inline void DropOldestThenPush(PlanarRingBuffer& ring,
                               float* dropScratch[2],
                               DriftController& drift,
                               const float* const channels[2],
                               std::size_t frames) {
  bool dropped = false;
  while (frames > ring.availableToWrite()) {
    if (ring.pop(dropScratch, 1) == 0) {
      break;
    }
    dropped = true;
  }
  ring.push(channels, frames);
  if (dropped) {
    drift.notifyOverrun();
  }
}

}  // namespace apm44
