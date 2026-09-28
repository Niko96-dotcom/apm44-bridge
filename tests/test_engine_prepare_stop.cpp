#include "engine/BridgeEngine.h"

#include <apm44/MmapShmRing.h>

#include <catch2/catch_test_macros.hpp>

#include <chrono>

TEST_CASE("prepare in virtual-device mode aborts promptly when stop is requested",
          "[engine][prepare][stop]") {
  // BridgeEngine waits on the production ring name (kShmRingName) through its
  // default-constructed VirtualDeviceFeed, which offers no injection point for
  // a pid-suffixed test ring (the "/apm44t<pid>.." mechanism the shm unit
  // tests use to avoid colliding with a real driver). So the missing-ring
  // case is arranged by requiring the real driver ring to be absent. This
  // test never creates or unlinks kShmRingName: unlinking would destroy a
  // real driver's ring.
  apm44::MmapShmRing probe;
  if (probe.open(apm44::ShmRingRole::Observer)) {
    probe.close();
    SKIP("real APM44 Bridge shm ring is present; missing-ring case not applicable");
  }

  apm44::BridgeDevicePair devices;
  apm44::BridgeEngineOptions options;
  options.virtualDevice = true;

  apm44::BridgeEngine engine;
  apm44::BridgeEngine::requestStop();
  const auto start = std::chrono::steady_clock::now();
  const bool prepared = engine.prepare(devices, options);
  const auto elapsed = std::chrono::steady_clock::now() - start;

  CHECK_FALSE(prepared);
  CHECK(engine.stopRequestedDuringPrepare());
  CHECK(elapsed < std::chrono::seconds(1));

  apm44::BridgeEngine::clearStopRequestForTesting();
}
