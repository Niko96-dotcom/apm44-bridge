#include <catch2/catch_test_macros.hpp>

#include "apm44/PlanarRingBuffer.h"

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

TEST_CASE("PlanarRingBuffer capacity enforced", "[planar_ring]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(4);

  float ch0[4] = {1, 1, 1, 1};
  float ch1[4] = {2, 2, 2, 2};
  const float* in[2] = {ch0, ch1};
  REQUIRE(ring.push(in, 4) == 3);
  REQUIRE(ring.push(in, 1) == 0);
}
