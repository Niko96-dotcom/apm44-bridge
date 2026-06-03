#include "engine/VirtualDeviceFeed.h"

#include "apm44/MmapShmRing.h"
#include "apm44/PlanarRingBuffer.h"

#include <catch2/catch_test_macros.hpp>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <string>
#include <vector>

namespace {

std::string TestRingName() {
  return "/apm44t" + std::to_string(static_cast<long long>(getpid())) + "f";
}

}  // namespace

TEST_CASE("VirtualDeviceFeed drains shm into ring", "[virtual_device]") {
  const std::string ringName = TestRingName();
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  std::vector<float> interleaved(64);
  for (std::size_t i = 0; i < 32; ++i) {
    interleaved[i * 2] = 0.1f;
    interleaved[i * 2 + 1] = 0.2f;
  }
  REQUIRE(producer.pushInterleaved(interleaved.data(), 32) == 32);
  producer.close();

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  apm44::PlanarRingBuffer ring;
  ring.prepare(1024);
  const std::size_t pushed = feed.drainTo(ring, 64);
  REQUIRE(pushed == 32);
  REQUIRE(ring.fillFrames() == 32);

  feed.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("VirtualDeviceFeed leaves shm untouched when destination ring is full",
          "[virtual_device]") {
  const std::string ringName = TestRingName();
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  std::vector<float> interleaved(16);
  for (std::size_t i = 0; i < 8; ++i) {
    interleaved[i * 2 + 0] = static_cast<float>(i);
    interleaved[i * 2 + 1] = -static_cast<float>(i);
  }
  REQUIRE(producer.pushInterleaved(interleaved.data(), 8) == 8);

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  apm44::PlanarRingBuffer fullRing;
  fullRing.prepare(8);
  std::vector<float> fill0(7, 1.0f);
  std::vector<float> fill1(7, 1.0f);
  const float* fillCh[2] = {fill0.data(), fill1.data()};
  REQUIRE(fullRing.push(fillCh, 7) == 7);
  REQUIRE(fullRing.availableToWrite() == 0);

  REQUIRE(feed.drainTo(fullRing, 8) == 0);
  feed.close();

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  std::vector<float> out(16);
  REQUIRE(consumer.popInterleaved(out.data(), 8) == 8);
  for (std::size_t i = 0; i < 16; ++i) {
    REQUIRE(out[i] == interleaved[i]);
  }

  producer.close();
  consumer.close();
  shm_unlink(ringName.c_str());
}
