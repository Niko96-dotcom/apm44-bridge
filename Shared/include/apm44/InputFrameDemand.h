#pragma once

#include <cstddef>

namespace apm44 {

// Converts output callback frame counts into input-rate frame demand without
// accumulating rounding error across callbacks.
class InputFrameDemand {
 public:
  void reset();
  std::size_t consume(std::size_t outputFrames, double srcRatio);

 private:
  double fractionalFrames_ = 0.0;
};

}  // namespace apm44
