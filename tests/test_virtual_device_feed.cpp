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
    interleaved[i * 2] = static_cast<float>(i);
    interleaved[i * 2 + 1] = -static_cast<float>(i);
  }
  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());
  feed.markReady();
  REQUIRE(producer.pushInterleaved(interleaved.data(), 32) == 32);

  apm44::PlanarRingBuffer ring;
  ring.prepare(1024);
  const std::size_t pushed = feed.drainTo(ring, 64);
  REQUIRE(pushed == 32);
  REQUIRE(ring.fillFrames() == 32);

  float left[32] = {};
  float right[32] = {};
  float* output[2] = {left, right};
  REQUIRE(ring.pop(output, 32) == 32);
  for (std::size_t i = 0; i < 32; ++i) {
    REQUIRE(left[i] == interleaved[i * 2]);
    REQUIRE(right[i] == interleaved[i * 2 + 1]);
  }

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
  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());
  feed.markReady();
  REQUIRE(producer.pushInterleaved(interleaved.data(), 8) == 8);

  apm44::PlanarRingBuffer fullRing;
  fullRing.prepare(8);
  std::vector<float> fill0(7, 1.0f);
  std::vector<float> fill1(7, 1.0f);
  const float* fillCh[2] = {fill0.data(), fill1.data()};
  REQUIRE(fullRing.push(fillCh, 7) == 7);
  REQUIRE(fullRing.availableToWrite() == 0);

  REQUIRE(feed.drainTo(fullRing, 8) == 0);
  REQUIRE(producer.header()->read_index.load(std::memory_order_acquire) == 0);
  REQUIRE(producer.header()->write_index.load(std::memory_order_acquire) == 8);
  feed.close();

  producer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("VirtualDeviceFeed drains a complete 4096-frame DAW burst in one pass",
          "[virtual_device][large_callback][regression]") {
  const std::string ringName = TestRingName();
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(apm44::kDefaultShmCapacityFrames));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());
  feed.markReady();

  constexpr std::size_t kCallbackFrames = 4096;
  std::vector<float> interleaved(kCallbackFrames * 2, 0.25f);
  REQUIRE(producer.pushInterleaved(interleaved.data(), kCallbackFrames) ==
          kCallbackFrames);

  apm44::PlanarRingBuffer ring;
  ring.prepare(apm44::kDefaultShmCapacityFrames + 512);
  REQUIRE(feed.drainTo(ring, ring.availableToWrite()) == kCallbackFrames);
  REQUIRE(ring.fillFrames() == kCallbackFrames);
  REQUIRE(producer.header()->read_index.load(std::memory_order_acquire) ==
          producer.header()->write_index.load(std::memory_order_acquire));

  feed.close();
  producer.close();
  shm_unlink(ringName.c_str());
}
