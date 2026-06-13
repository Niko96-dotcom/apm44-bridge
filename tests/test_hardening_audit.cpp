#include <catch2/catch_test_macros.hpp>

#include "apm44/DriftController.h"
#include "apm44/MmapShmRing.h"
#include "apm44/PlanarRingBuffer.h"
#include "engine/BridgeControlLoop.h"
#include "engine/BridgeInputOverrun.h"

#include <chrono>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {

std::string ReadFile(const char* path) {
  for (const std::string prefix : {"", "../", "../../"}) {
    std::ifstream in(prefix + path);
    if (in) {
      return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    }
  }
  return {};
}

bool Contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

}  // namespace

TEST_CASE("MmapShmRing closed ring returns zero safely", "[hardening_audit]") {
  apm44::MmapShmRing ring;
  REQUIRE_FALSE(ring.isMapped());

  float interleaved[4] = {1.0f, 2.0f, 3.0f, 4.0f};
  float out0[4] = {};
  float out1[4] = {};
  float* planar[2] = {out0, out1};

  REQUIRE(ring.pushInterleaved(interleaved, 2) == 0);
  REQUIRE(ring.popInterleaved(interleaved, 2) == 0);
  REQUIRE(ring.popToPlanar(planar, 2) == 0);
  ring.setDaemonReady();
}

TEST_CASE("PlanarRingBuffer drop-input overrun preserves consumer-visible fill", "[hardening_audit][SEC-02]") {
  // RT-01 / RT-02 contract: the producer path drops the unaccepted tail
  // of the incoming block (drop-new-input policy) and never calls `pop`
  // from the producer side. Consumer-visible fill is therefore preserved
  // exactly; the incoming 2 frames do not enter the ring.
  apm44::PlanarRingBuffer ring;
  ring.prepare(4);

  float ch0[4] = {1, 2, 3, 4};
  float ch1[4] = {5, 6, 7, 8};
  const float* in[2] = {ch0, ch1};
  REQUIRE(ring.push(in, 3) == 3);

  float drop0[1] = {};
  float drop1[1] = {};
  float* dropScratch[2] = {drop0, drop1};
  apm44::DriftController drift;
  drift.reset();

  const float new0[2] = {90, 91};
  const float new1[2] = {92, 93};
  const float* incoming[2] = {new0, new1};
  apm44::PushDroppingNewInput(ring, dropScratch, drift, incoming, 2);

  // Overrun was reported, fill preserved at 3 (no producer-side pop).
  REQUIRE(ring.availableToRead() == 3);
  REQUIRE(drift.overrunCount() == 1);

  // Consumer pops the original 3 frames — they are unchanged, the
  // incoming 2 frames were dropped, not stored.
  float out0[3] = {};
  float out1[3] = {};
  float* out[2] = {out0, out1};
  REQUIRE(ring.pop(out, 3) == 3);
  REQUIRE(out0[0] == 1.0f);
  REQUIRE(out0[1] == 2.0f);
  REQUIRE(out0[2] == 3.0f);
  REQUIRE(out1[0] == 5.0f);
  REQUIRE(out1[1] == 6.0f);
  REQUIRE(out1[2] == 7.0f);
}

TEST_CASE("kMaxCallbackFrames matches scratch capacity constant", "[hardening_audit]") {
  STATIC_REQUIRE(apm44::kMaxCallbackFrames == 1024);
}

TEST_CASE("kControlLoopInterval blocks at least 100ms", "[hardening_audit]") {
  STATIC_REQUIRE(apm44::kControlLoopInterval >= std::chrono::milliseconds(100));
}

TEST_CASE("virtual-device output-start failure cleanup avoids null input stop",
          "[hardening_audit][AUD-01][AUD-03][CORE-01]") {
  const std::string source = ReadFile("BridgeDaemon/src/engine/BridgeEngine.cpp");

  REQUIRE(Contains(source, "bool inputStarted = false;"));
  REQUIRE(Contains(source, "cleanupIOProcs(inputStarted, false);"));
  REQUIRE_FALSE(Contains(source, "AudioDeviceStop(devices_.input.deviceId, inputProc_);\n    stop();"));
}

TEST_CASE("no WriteSilence helper exists in IoProcHandlers",
          "[hardening_audit][SEC-03]") {
  // SEC-03: the old/incorrect WriteSilence helper must not be present.
  // Silence generation is performed inline by OutputIoProc; no dead helper
  // should remain to contradict the contract.
  const std::string source = ReadFile("BridgeDaemon/src/engine/IoProcHandlers.cpp");

  REQUIRE_FALSE(Contains(source, "WriteSilence"));
}
