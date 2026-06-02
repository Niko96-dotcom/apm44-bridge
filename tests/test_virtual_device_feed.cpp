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
