#include "engine/VirtualDeviceFeed.h"

#include "apm44/MmapShmRing.h"
#include "apm44/ShmRingLayout.h"

#include <catch2/catch_test_macros.hpp>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstring>
#include <string>

namespace {

std::string TestRingName(char suffix) {
  return "/apm44t" + std::to_string(static_cast<long long>(getpid())) + suffix;
}

void UnlinkRing(const std::string& name) { ::shm_unlink(name.c_str()); }

bool CreateInvalidRing(const std::string& name) {
  UnlinkRing(name);
  const int fd = ::shm_open(name.c_str(), O_CREAT | O_RDWR | O_EXCL, 0666);
  if (fd < 0) {
    return false;
  }
  constexpr std::size_t kSize = 4096;
  if (::ftruncate(fd, static_cast<off_t>(kSize)) != 0) {
    ::close(fd);
    return false;
  }
  void* base = ::mmap(nullptr, kSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (base == MAP_FAILED) {
    ::close(fd);
    return false;
  }
  std::memset(base, 0, kSize);
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  header->magic = 0;
  header->version = 99;
  ::munmap(base, kSize);
  ::close(fd);
  return true;
}

}  // namespace

TEST_CASE("pollStaleRing returns Ok when ring is fresh", "[shm_stale_recovery]") {
  const std::string ringName = TestRingName('a');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());
  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::Ok);

  feed.close();
  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("pollStaleRing remaps after ring recreation", "[shm_stale_recovery]") {
  const std::string ringName = TestRingName('b');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(producer.create(512));

  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::Remapped);
  REQUIRE(feed.isOpen());
  REQUIRE_FALSE(feed.pollStaleRing() == apm44::StaleRingPollResult::MustExit);

  feed.close();
  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("pollStaleRing returns MustExit when recreated ring is invalid",
          "[shm_stale_recovery]") {
  const std::string ringName = TestRingName('c');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(CreateInvalidRing(ringName));

  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::MustExit);

  feed.close();
  UnlinkRing(ringName);
}
