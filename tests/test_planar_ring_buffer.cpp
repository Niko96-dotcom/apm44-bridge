#include <catch2/catch_test_macros.hpp>

#include "apm44/PlanarRingBuffer.h"
#include "engine/BridgeInputOverrun.h"

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

// RT-01 / RT-02 / RT-05: producer-side overrun handling must drop the
// unaccepted tail and return an overrun flag without ever calling
// `pop` from the producer path. The test instantiates a non-production
// `PlanarRingBuffer` directly — no `/apm44_bridge_ring` is touched.
TEST_CASE("ProducerPushDroppingNewInputDropsUnacceptedAndNotifiesOverrun",
          "[planar_ring][rt][RT-01][RT-02][SEC-02]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(8);  // capacity 8, max writable 7

  // Fill the ring to its max writable depth.
  float fillCh0[8] = {1, 1, 1, 1, 1, 1, 1, 1};
  float fillCh1[8] = {2, 2, 2, 2, 2, 2, 2, 2};
  const float* fillIn[2] = {fillCh0, fillCh1};
  REQUIRE(ring.push(fillIn, 7) == 7);
  REQUIRE(ring.availableToWrite() == 0);

  // Now the producer is invoked with another 4-frame block. The ring is
  // full; the producer must drop the unaccepted tail and bump the
  // overrun counter. It must NOT mutate the fill that the consumer will
  // see (no producer-side `pop`).
  float incCh0[4] = {9, 9, 9, 9};
  float incCh1[4] = {9, 9, 9, 9};
  const float* incIn[2] = {incCh0, incCh1};

  const bool inputOverrun = apm44::PushDroppingNewInput(ring, incIn, 4);

  REQUIRE(inputOverrun);
  // Consumer-visible fill is unchanged: 7 frames still pending read.
  REQUIRE(ring.availableToRead() == 7);
}

TEST_CASE("ProducerPathSucceedsWhenRingHasCapacity",
          "[planar_ring][rt][RT-01]") {
  apm44::PlanarRingBuffer ring;
  ring.prepare(8);

  float ch0[4] = {1, 2, 3, 4};
  float ch1[4] = {5, 6, 7, 8};
  const float* in[2] = {ch0, ch1};

  const bool inputOverrun = apm44::PushDroppingNewInput(ring, in, 4);

  // No overrun, and the consumer can read exactly the 4 pushed frames.
  REQUIRE_FALSE(inputOverrun);
  REQUIRE(ring.availableToRead() == 4);
}
