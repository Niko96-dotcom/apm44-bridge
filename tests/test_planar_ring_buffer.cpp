#include <catch2/catch_test_macros.hpp>

#include "apm44/PlanarRingBuffer.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

TEST_CASE("PlanarRingBuffer preserves samples across many wraps", "[planar_ring]") {
  // Replaces `PlanarRingBuffer push pop` and `PlanarRingBuffer 10k
  // push pop alternation`: a small ring forces index wraparound, and
  // every popped value (ch1 = -ch0, monotonically increasing) plus
  // the push/pop counts are asserted, so wraparound bugs are caught
  // (the old 10k test used zeroed data and only checked counts).
  apm44::PlanarRingBuffer ring;
  ring.prepare(8);
  const std::size_t capacity = ring.capacityFrames();

  float next = 1.0f;
  std::vector<float> in0(capacity);
  std::vector<float> in1(capacity);
  std::vector<float> out0(capacity);
  std::vector<float> out1(capacity);
  for (int i = 0; i < 10000; ++i) {
    // Varying count in 1..capacity-1 (one slot is reserved for the
    // SPSC full/empty distinction, so a full `capacity` push can
    // never be accepted in one go).
    const std::size_t count = static_cast<std::size_t>(i % (capacity - 1)) + 1;
    for (std::size_t k = 0; k < count; ++k) {
      in0[k] = next;
      in1[k] = -next;
      ++next;
    }
    const float* in[2] = {in0.data(), in1.data()};
    const std::size_t pushed = ring.push(in, count);
    REQUIRE(pushed == count);
    float* out[2] = {out0.data(), out1.data()};
    const std::size_t popped = ring.pop(out, pushed);
    REQUIRE(popped == pushed);
    for (std::size_t k = 0; k < popped; ++k) {
      const float expected = next - static_cast<float>(count - k);
      REQUIRE(out0[k] == expected);
      REQUIRE(out1[k] == -expected);
    }
  }
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
