#pragma once

#include <cstddef>

namespace apm44 {

class VirtualPrebufferGate {
 public:
  void reset(std::size_t targetFrames) {
    targetFrames_ = targetFrames;
    primed_ = false;
  }

  bool shouldOutput(std::size_t fillFrames) {
    if (primed_) {
      return true;
    }
    if (fillFrames < targetFrames_) {
      return false;
    }
    primed_ = true;
    return true;
  }

  void forceRebuffer() { primed_ = false; }
  bool primed() const { return primed_; }

 private:
  std::size_t targetFrames_ = 0;
  bool primed_ = false;
};

}  // namespace apm44
