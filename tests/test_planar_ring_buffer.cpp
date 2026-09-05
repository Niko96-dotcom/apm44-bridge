#include <catch2/catch_test_macros.hpp>

#include "apm44/PlanarRingBuffer.h"

#include <cmath>
#include <cstdint>

TEST_CASE("PlanarRingBuffer push pop", "[planar_ring]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(8);

  float ch0[4] = {1, 2, 3, 4};
  float ch1[4] = {5, 6, 7, 8};
  const float* in[2] = {ch0, ch1};
  REQUIRE(ring.push(in, 4) == 4);

  float out0[4] = {};
  float out1[4] = {};
  float* out[2] = {out0, out1};
  REQUIRE(ring.pop(out, 4) == 4);
  REQUIRE(out0[0] == 1.0f);
  REQUIRE(out1[3] == 8.0f);
}

TEST_CASE("PlanarRingBuffer power-of-two capacity rounding", "[planar_ring]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(100);
  REQUIRE(ring.capacityFrames() == 128);
  REQUIRE(ring.availableToWrite() == 127);
}

TEST_CASE("PlanarRingBuffer capacity enforced SPSC reserve slot", "[planar_ring]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(4);

  float ch0[4] = {1, 1, 1, 1};
  float ch1[4] = {2, 2, 2, 2};
  const float* in[2] = {ch0, ch1};
  REQUIRE(ring.push(in, 4) == 3);
  REQUIRE(ring.push(in, 1) == 0);
}

TEST_CASE("PlanarRingBuffer fillMs at 44100 Hz", "[planar_ring]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(1024);
  const std::size_t targetFrames =
      apm44::PlanarRingBuffer::framesForMilliseconds(15.0, 44100.0);
  REQUIRE(targetFrames == 662);

  std::vector<float> ch0(targetFrames, 1.0f);
  std::vector<float> ch1(targetFrames, 2.0f);
  const float* in[2] = {ch0.data(), ch1.data()};
  REQUIRE(ring.push(in, targetFrames) == targetFrames);

  const double ms = ring.fillMs(44100.0);
  REQUIRE(std::abs(ms - 15.0) < 0.5);
}

TEST_CASE("PlanarRingBuffer 10k push pop alternation", "[planar_ring]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(64);

  float ch0[32] = {};
  float ch1[32] = {};
  float out0[32] = {};
  float out1[32] = {};
  const float* in[2] = {ch0, ch1};
  float* out[2] = {out0, out1};

  for (int i = 0; i < 10000; ++i) {
    const std::size_t pushed = ring.push(in, 16);
    if (pushed > 0) {
      const std::size_t popped = ring.pop(out, pushed);
      REQUIRE(popped == pushed);
    }
  }
}

TEST_CASE("PlanarRingBuffer drops the unaccepted tail and preserves queued audio",
          "[planar_ring][rt]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(8);
  const float left[6] = {1, 2, 3, 4, 5, 6};
  const float right[6] = {-1, -2, -3, -4, -5, -6};
  const float* input[2] = {left, right};
  REQUIRE(ring.push(input, 6) == 6);

  const float newLeft[2] = {7, 99};
  const float newRight[2] = {-7, -99};
  const float* incoming[2] = {newLeft, newRight};
  REQUIRE(ring.push(incoming, 2) == 1);
  REQUIRE(ring.push(incoming, 2) == 0);
  REQUIRE(ring.availableToRead() == 7);

  float outLeft[7] = {};
  float outRight[7] = {};
  float* output[2] = {outLeft, outRight};
  REQUIRE(ring.pop(output, 7) == 7);
  for (int i = 0; i < 7; ++i) {
    REQUIRE(outLeft[i] == static_cast<float>(i + 1));
    REQUIRE(outRight[i] == -static_cast<float>(i + 1));
  }
}
