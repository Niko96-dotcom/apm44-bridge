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
  // Generous upper bound: shared CI runners (and TSan builds) oversleep.
  REQUIRE(elapsed < timeout + std::chrono::milliseconds(500));
}

TEST_CASE("WaitForStopOrTimeout observes an existing stop request", "[control_loop_wait]") {
  const auto start = std::chrono::steady_clock::now();
  const bool stopped = apm44::WaitForStopOrTimeout(std::chrono::seconds(2),
                                                    [] { return true; });
  const auto elapsed = std::chrono::steady_clock::now() - start;

  REQUIRE(stopped);
  REQUIRE(elapsed < std::chrono::milliseconds(200));
}

TEST_CASE("WaitForStopOrTimeout observes a stop request during polling", "[control_loop_wait]") {
  const auto timeout = std::chrono::seconds(2);
  std::atomic<bool> stopRequested{false};
  std::atomic<std::chrono::steady_clock::rep> requestedAt{0};
  std::thread setter([&stopRequested, &requestedAt] {
    std::this_thread::sleep_for(std::chrono::milliseconds(30));
    requestedAt.store(std::chrono::steady_clock::now().time_since_epoch().count(),
                      std::memory_order_relaxed);
    stopRequested.store(true, std::memory_order_release);
  });

  const auto start = std::chrono::steady_clock::now();
  const bool stopped = apm44::WaitForStopOrTimeout(
      timeout,
      [&stopRequested] { return stopRequested.load(std::memory_order_acquire); });
  const auto returnedAt = std::chrono::steady_clock::now();
  setter.join();

  REQUIRE(stopped);
  // Measure from the stop request, not from thread start: a loaded runner
  // can oversleep the setter's delay, which says nothing about the wait.
  const auto requested = std::chrono::steady_clock::time_point(
      std::chrono::steady_clock::duration(requestedAt.load(std::memory_order_relaxed)));
  REQUIRE(returnedAt - requested < std::chrono::milliseconds(250));
  REQUIRE(returnedAt - start < timeout);
}
