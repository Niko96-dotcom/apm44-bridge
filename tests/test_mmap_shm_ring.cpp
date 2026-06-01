#include "apm44/MmapShmRing.h"
#include "apm44/PlanarRingBuffer.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

#include <fcntl.h>
#include <sys/mman.h>

#include <cmath>
#include <vector>

TEST_CASE("MmapShmRing producer consumer round trip", "[mmap_shm_ring]") {
  apm44::MmapShmRing producer;
  REQUIRE(producer.create(1024));

  apm44::MmapShmRing consumer;
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  std::vector<float> interleaved(200);
  for (std::size_t i = 0; i < 100; ++i) {
    interleaved[i * 2 + 0] = std::sin(static_cast<float>(i) * 0.1f);
    interleaved[i * 2 + 1] = -interleaved[i * 2 + 0];
  }

  const std::size_t pushed = producer.pushInterleaved(interleaved.data(), 100);
  REQUIRE(pushed == 100);

  std::vector<float> out(200);
  const std::size_t popped = consumer.popInterleaved(out.data(), 100);
  REQUIRE(popped >= 95);

  for (std::size_t i = 0; i < popped; ++i) {
    REQUIRE(out[i * 2 + 0] == Catch::Approx(interleaved[i * 2 + 0]).margin(1e-6f));
    REQUIRE(out[i * 2 + 1] == Catch::Approx(interleaved[i * 2 + 1]).margin(1e-6f));
  }

  producer.close();
  consumer.close();
  shm_unlink(apm44::kShmRingName);
}

TEST_CASE("MmapShmRing popToPlanar feeds planar buffer", "[mmap_shm_ring]") {
  apm44::MmapShmRing producer;
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer;
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  std::vector<float> interleaved(64);
  for (std::size_t i = 0; i < 32; ++i) {
    interleaved[i * 2] = 0.25f;
    interleaved[i * 2 + 1] = 0.75f;
  }
  REQUIRE(producer.pushInterleaved(interleaved.data(), 32) == 32);

  std::vector<float> ch0(32), ch1(32);
  float* channels[2] = {ch0.data(), ch1.data()};
  REQUIRE(consumer.popToPlanar(channels, 32) == 32);
  REQUIRE(ch0[10] == Catch::Approx(0.25f));
  REQUIRE(ch1[10] == Catch::Approx(0.75f));

  producer.close();
  consumer.close();
  shm_unlink(apm44::kShmRingName);
}
