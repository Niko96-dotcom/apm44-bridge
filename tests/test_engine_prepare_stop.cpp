#include "ParentDeathWatch.h"
#include "engine/BridgeEngine.h"
#include "engine/BridgeMetrics.h"

#include <apm44/AudioFormats.h>

#include <catch2/catch_test_macros.hpp>

#include <unistd.h>

#include <chrono>
#include <string>
#include <thread>

namespace {

// An isolated, never-created ring name ("/apm44t<pid>.." like the shm unit
// tests; macOS limits shm names to 31 chars). Virtual-device prepare waits on
// it instead of the production ring, so these tests neither read nor create
// kShmRingName and behave the same whether or not a real driver is loaded.
std::string AbsentRingName(const std::string& suffix) {
  return "/apm44t" + std::to_string(static_cast<long long>(::getpid())) + suffix;
}

}  // namespace

TEST_CASE("prepare in virtual-device mode aborts promptly when stop is requested",
          "[engine][prepare][stop]") {
  apm44::BridgeDevicePair devices;
  apm44::BridgeEngineOptions options;
  options.virtualDevice = true;

  apm44::BridgeEngine engine(AbsentRingName("s"));
  apm44::BridgeEngine::requestStop();
  const auto start = std::chrono::steady_clock::now();
  const bool prepared = engine.prepare(devices, options);
  const auto elapsed = std::chrono::steady_clock::now() - start;

  CHECK_FALSE(prepared);
  CHECK(engine.stopRequestedDuringPrepare());
  CHECK(elapsed < std::chrono::seconds(1));

  apm44::BridgeEngine::clearStopRequestForTesting();
}

namespace {

apm44::BridgeDevicePair MakeStereoPair() {
  apm44::BridgeDevicePair devices;
  devices.inputAsbd = apm44::MakeFloat32StereoNonInterleaved(apm44::kInputSampleRate);
  devices.outputAsbd = apm44::MakeFloat32StereoNonInterleaved(apm44::kOutputSampleRate);
  return devices;
}

// The JSON line the daemon would emit for this engine's metrics tick.
std::string MetricsLineFor(const apm44::BridgeEngine& engine) {
  return apm44::ToJsonLine(apm44::MakeBridgeMetrics(
      engine.metricsSnapshot(), engine.effectiveTargetFillMs(), "medium"));
}

}  // namespace

TEST_CASE("the parent-death watcher stops the running control loop promptly",
          "[engine][stop][F-07]") {
  apm44::BridgeEngine::clearStopRequestForTesting();
  apm44::BridgeEngine engine;
  REQUIRE(engine.prepare(MakeStereoPair()));

  // Production wiring: the detached watcher thread calls requestStop() while
  // the control loop polls the stop flag on this thread.
  int channel[2] = {-1, -1};
  REQUIRE(::pipe(channel) == 0);
  apm44::StartParentDeathWatch(channel[0], &apm44::BridgeEngine::requestStop);

  int ticks = 0;
  bool guardTripped = false;
  std::chrono::steady_clock::time_point closedAt;
  engine.runUntilSignal([&](const apm44::BridgeEngine&) {
    ++ticks;
    if (ticks == 1) {
      closedAt = std::chrono::steady_clock::now();
      ::close(channel[1]);
    } else if (ticks > 4) {
      // Several control intervals passed without the watcher's stop landing.
      guardTripped = true;
      apm44::BridgeEngine::requestStop();
    }
  });
  const auto elapsed = std::chrono::steady_clock::now() - closedAt;

  CHECK_FALSE(guardTripped);
  CHECK(elapsed < std::chrono::seconds(1));
  ::close(channel[0]);
  apm44::BridgeEngine::clearStopRequestForTesting();
}

TEST_CASE("metrics report the target fill a non-virtual engine prepared with",
          "[engine][metrics][A003]") {
  apm44::BridgeEngineOptions options;
  options.virtualDevice = false;

  SECTION("a low request is kept for the BlackHole/input path") {
    options.targetFillMs = 8.0;
    apm44::BridgeEngine engine;
    REQUIRE(engine.prepare(MakeStereoPair(), options));
    CHECK(engine.effectiveTargetFillMs() == 8.0);
    CHECK(MetricsLineFor(engine).find("\"target_fill_ms\":8.000") != std::string::npos);
  }
  SECTION("a high request is kept") {
    options.targetFillMs = 60.0;
    apm44::BridgeEngine engine;
    REQUIRE(engine.prepare(MakeStereoPair(), options));
    CHECK(engine.effectiveTargetFillMs() == 60.0);
    CHECK(MetricsLineFor(engine).find("\"target_fill_ms\":60.000") != std::string::npos);
  }
}

TEST_CASE("metrics report the HAL floor a virtual-device engine prepared with",
          "[engine][metrics][A003]") {
  // Virtual-device prepare waits on the engine's shm ring, here an absent
  // isolated one, with stop pre-requested so prepare returns at once. The
  // effective target is resolved before that wait, so it is observable on the
  // failed prepare.
  apm44::BridgeEngineOptions options;
  options.virtualDevice = true;
  double expectedMs = 0.0;
  std::string expectedJson;

  SECTION("a request below the floor is raised to it") {
    options.targetFillMs = 8.0;
    expectedMs = apm44::kHalTargetFillFloorMs;
    expectedJson = "\"target_fill_ms\":20.000";
  }
  SECTION("a request above the floor is kept") {
    options.targetFillMs = 60.0;
    expectedMs = 60.0;
    expectedJson = "\"target_fill_ms\":60.000";
  }

  apm44::BridgeEngine engine(AbsentRingName("m"));
  apm44::BridgeEngine::requestStop();
  REQUIRE_FALSE(engine.prepare(MakeStereoPair(), options));
  apm44::BridgeEngine::clearStopRequestForTesting();

  CHECK(engine.effectiveTargetFillMs() == expectedMs);
  CHECK(MetricsLineFor(engine).find(expectedJson) != std::string::npos);
}
