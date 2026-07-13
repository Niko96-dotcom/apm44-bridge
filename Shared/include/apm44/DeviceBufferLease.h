#pragma once

#include <cstddef>

namespace apm44 {

// Records the device state changed by one bridge session. Restoration is
// allowed only while the device still has the value this session requested;
// a later change by another Core Audio client always wins.
struct DeviceBufferLease {
  std::size_t originalFrames = 0;
  std::size_t requestedFrames = 0;
  bool changedByBridge = false;

  void begin(std::size_t original, std::size_t requested) {
    originalFrames = original;
    requestedFrames = requested;
    changedByBridge = false;
  }

  void markChanged() { changedByBridge = true; }

  bool shouldRestore(std::size_t currentFrames) const {
    return changedByBridge && originalFrames > 0 && requestedFrames > 0 &&
           currentFrames == requestedFrames;
  }

  void reset() { *this = {}; }
};

}  // namespace apm44
