#include <catch2/catch_test_macros.hpp>

#include "engine/BridgeControlLoop.h"

#include <atomic>
#include <chrono>
#include <thread>

TEST_CASE("WaitForStopOrTimeout waits for its deadline", "[control_loop_wait]") {
  const auto timeout = std::chrono::milliseconds(60);
  const auto start = std::chrono::steady_clock::now();
  const bool stopped = apm44::WaitForStopOrTimeout(timeout, [] { return false; });
  const auto elapsed = std::chrono::steady_clock::now() - start;

  REQUIRE_FALSE(stopped);
  REQUIRE(elapsed >= timeout);
  REQUIRE(elapsed < timeout + std::chrono::milliseconds(200));
}

TEST_CASE("WaitForStopOrTimeout observes an existing stop request", "[control_loop_wait]") {
  const auto start = std::chrono::steady_clock::now();
  const bool stopped = apm44::WaitForStopOrTimeout(std::chrono::seconds(2),
                                                    [] { return true; });
  const auto elapsed = std::chrono::steady_clock::now() - start;

  REQUIRE(stopped);
  REQUIRE(elapsed < std::chrono::milliseconds(20));
}

TEST_CASE("WaitForStopOrTimeout observes a stop request during polling", "[control_loop_wait]") {
  std::atomic<bool> stopRequested{false};
  const auto start = std::chrono::steady_clock::now();
  std::thread setter([&stopRequested] {
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    stopRequested.store(true, std::memory_order_release);
  });

  const bool stopped = apm44::WaitForStopOrTimeout(
      std::chrono::seconds(2),
      [&stopRequested] { return stopRequested.load(std::memory_order_acquire); });
  setter.join();
  const auto elapsed = std::chrono::steady_clock::now() - start;

  REQUIRE(stopped);
  REQUIRE(elapsed < std::chrono::milliseconds(130));
}
