// RT-03 / RT-04 / RT-05 regression tests for the oversized output callback
// safety contract implemented in `BridgeDaemon/src/engine/IoProcHandlers.cpp`.
//
// The contract: when Core Audio requests more frames than the engine can
// render in one call, the interleaved and non-interleaved output paths
// must write or explicitly silence every frame in the destination
// buffer. Stale tail samples are not acceptable.
//
// We exercise the contract by reproducing the same render-then-silence
// control flow used inside `OutputIoProc` (without spinning up a real
// `BridgeEngine`, which needs Core Audio device IDs). A future refactor
// that drops the tail-silence loops from `OutputIoProc` should be paired
// with a corresponding update here — this test is the executable
// specification of the contract.
//
// Tests do not touch `/apm44_bridge_ring` (RT-05).

#include <catch2/catch_test_macros.hpp>

#include <algorithm>
#include <cstring>
#include <vector>

namespace {

constexpr std::size_t kMaxCallbackFrames = 1024;
constexpr std::size_t kChannels = 2;

// Mirrors the interleaved output callback in IoProcHandlers.cpp.
void RenderInterleavedOutput(std::vector<float>& interleaved,
                             std::size_t requestedFrames,
                             std::size_t scratchCapacity) {
  const std::size_t framesToRender = std::min(requestedFrames, scratchCapacity);
  for (std::size_t i = 0; i < framesToRender; ++i) {
    interleaved[i * 2 + 0] = static_cast<float>(i);
    interleaved[i * 2 + 1] = -static_cast<float>(i);
  }
  for (std::size_t i = framesToRender; i < requestedFrames; ++i) {
    interleaved[i * 2 + 0] = 0.0f;
    interleaved[i * 2 + 1] = 0.0f;
  }
}

// Mirrors the non-interleaved output callback in IoProcHandlers.cpp.
void RenderNonInterleavedOutput(std::vector<float>& b0,
                                std::vector<float>& b1,
                                std::size_t requestedFrames,
                                std::size_t scratchCapacity) {
  const std::size_t framesToRender = std::min(requestedFrames, scratchCapacity);
  for (std::size_t i = 0; i < framesToRender; ++i) {
    b0[i] = static_cast<float>(i);
    b1[i] = -static_cast<float>(i);
  }
  for (std::size_t i = framesToRender; i < b0.size(); ++i) {
    b0[i] = 0.0f;
  }
  for (std::size_t i = framesToRender; i < b1.size(); ++i) {
    b1[i] = 0.0f;
  }
}

// Mirrors the mismatched non-interleaved input buffer sizing in
// IoProcHandlers.cpp. The input callback must never process more frames
// than the shortest channel buffer actually contains.
std::size_t MismatchedNonInterleavedInputFrames(std::size_t b0Bytes,
                                                std::size_t b1Bytes,
                                                std::size_t scratchCapacity) {
  const std::size_t b0Frames = b0Bytes / sizeof(float);
  const std::size_t b1Frames = b1Bytes / sizeof(float);
  return std::min(std::min(b0Frames, b1Frames), scratchCapacity);
}

}  // namespace

TEST_CASE("OversizedInterleavedOutputSilencesTail", "[io_proc][rt][RT-03][RT-04]") {
  // Core Audio asks for 4× the scratch capacity; the engine renders into
  // the first `scratch` frames, the tail is explicitly zeroed.
  constexpr std::size_t scratchCapacity = 64;
  constexpr std::size_t requestedFrames = scratchCapacity * 4;
  std::vector<float> interleaved(requestedFrames * kChannels, 0.5f);

  RenderInterleavedOutput(interleaved, requestedFrames, scratchCapacity);

  for (std::size_t i = 0; i < scratchCapacity; ++i) {
    REQUIRE(interleaved[i * 2 + 0] == static_cast<float>(i));
    REQUIRE(interleaved[i * 2 + 1] == -static_cast<float>(i));
  }
  for (std::size_t i = scratchCapacity; i < requestedFrames; ++i) {
    REQUIRE(interleaved[i * 2 + 0] == 0.0f);
    REQUIRE(interleaved[i * 2 + 1] == 0.0f);
  }
}

TEST_CASE("OversizedNonInterleavedOutputSilencesTail", "[io_proc][rt][RT-03][RT-04]") {
  constexpr std::size_t scratchCapacity = 64;
  constexpr std::size_t requestedFrames = scratchCapacity * 4;
  std::vector<float> b0(requestedFrames, 0.5f);
  std::vector<float> b1(requestedFrames, 0.5f);

  RenderNonInterleavedOutput(b0, b1, requestedFrames, scratchCapacity);

  for (std::size_t i = 0; i < scratchCapacity; ++i) {
    REQUIRE(b0[i] == static_cast<float>(i));
    REQUIRE(b1[i] == -static_cast<float>(i));
  }
  for (std::size_t i = scratchCapacity; i < requestedFrames; ++i) {
    REQUIRE(b0[i] == 0.0f);
    REQUIRE(b1[i] == 0.0f);
  }
}

TEST_CASE("InterleavedOutputWithinScratchCapacity", "[io_proc][rt][RT-03]") {
  // Sanity: when Core Audio asks for less than scratch, every frame is
  // rendered and there is no tail to silence.
  constexpr std::size_t scratchCapacity = kMaxCallbackFrames;
  constexpr std::size_t requestedFrames = 256;
  std::vector<float> interleaved(requestedFrames * kChannels, 0.5f);

  RenderInterleavedOutput(interleaved, requestedFrames, scratchCapacity);

  for (std::size_t i = 0; i < requestedFrames; ++i) {
    REQUIRE(interleaved[i * 2 + 0] == static_cast<float>(i));
    REQUIRE(interleaved[i * 2 + 1] == -static_cast<float>(i));
  }
}

TEST_CASE("InterleavedOutputAtScratchCapacityBoundary", "[io_proc][rt][RT-03][RT-04]") {
  // Edge case: requested == scratch → no tail to silence, but the loop
  // must not off-by-one.
  constexpr std::size_t scratchCapacity = 64;
  constexpr std::size_t requestedFrames = 64;
  std::vector<float> interleaved(requestedFrames * kChannels, 0.5f);

  RenderInterleavedOutput(interleaved, requestedFrames, scratchCapacity);

  for (std::size_t i = 0; i < requestedFrames; ++i) {
    REQUIRE(interleaved[i * 2 + 0] == static_cast<float>(i));
    REQUIRE(interleaved[i * 2 + 1] == -static_cast<float>(i));
  }
}

TEST_CASE("mismatched non-interleaved input buffer sizes use shortest channel",
          "[io_proc][rt][AUD-02][AUD-03]") {
  const std::size_t b0Bytes = 512 * sizeof(float);
  const std::size_t b1Bytes = 128 * sizeof(float);

  REQUIRE(MismatchedNonInterleavedInputFrames(b0Bytes, b1Bytes, kMaxCallbackFrames) == 128);
}
