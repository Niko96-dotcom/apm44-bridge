#pragma once

#include <string>

#include "apm44/MmapShmRing.h"

namespace apm44 {

// Debounces ProducerBuildMismatch open failures in BridgeEngine::prepare().
// A consumer that opens while the producer is mid-create() can briefly
// observe a half-published header; that transient must keep polling, not
// fail the daemon with the sticky exit-44 "older driver" error. The
// mismatch is fatal only after `required` consecutive observations with an
// identical detail string; any different result resets the streak.
class ShmMismatchDebounce {
 public:
  explicit ShmMismatchDebounce(int required = 3)
      : required_(required < 1 ? 1 : required) {}

  // Returns true once the streak reaches the required count (fatal).
  bool observe(ShmRingErrorCode code, const std::string& detail) {
    if (code != ShmRingErrorCode::ProducerBuildMismatch) {
      reset();
      return false;
    }
    if (streak_ == 0 || detail != lastDetail_) {
      streak_ = 1;
      lastDetail_ = detail;
    } else {
      ++streak_;
    }
    return streak_ >= required_;
  }

  void reset() {
    streak_ = 0;
    lastDetail_.clear();
  }

 private:
  int required_;
  int streak_ = 0;
  std::string lastDetail_;
};

}  // namespace apm44
