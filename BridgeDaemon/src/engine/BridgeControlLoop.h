#pragma once

#include <chrono>
#include <cstddef>
#include <thread>

namespace apm44 {

inline constexpr auto kControlLoopInterval = std::chrono::milliseconds(500);
inline constexpr auto kStopPollSlice = std::chrono::milliseconds(10);
inline constexpr std::size_t kMaxCallbackFrames = 1024;

template <class ShouldStop>
bool WaitForStopOrTimeout(std::chrono::steady_clock::duration timeout,
                           ShouldStop&& shouldStop,
                           std::chrono::steady_clock::duration slice = kStopPollSlice) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  if (shouldStop()) {
    return true;
  }

  while (true) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline) {
      return false;
    }
    const auto remaining = deadline - now;
    std::this_thread::sleep_for(remaining < slice ? remaining : slice);
    if (shouldStop()) {
      return true;
    }
  }
}

}  // namespace apm44
