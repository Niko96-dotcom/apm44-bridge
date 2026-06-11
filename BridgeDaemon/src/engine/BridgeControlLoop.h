#pragma once

#include <chrono>
#include <cstddef>

namespace apm44 {

inline constexpr auto kControlLoopInterval = std::chrono::milliseconds(500);
inline constexpr std::size_t kMaxCallbackFrames = 1024;

}  // namespace apm44
