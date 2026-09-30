#include "engine/StaleRingRecoveryPlan.h"
#include "engine/VirtualDeviceFeed.h"

#include "apm44/MmapShmRing.h"
#include "apm44/PlanarRingBuffer.h"
#include "apm44/ShmRingLayout.h"

#include <catch2/catch_test_macros.hpp>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstring>
#include <string>
#include <vector>

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

bool OverwriteProducerBuildId(const std::string& name, const char* buildId) {
  const int fd = ::shm_open(name.c_str(), O_RDWR, 0666);
  if (fd < 0) {
    return false;
  }
  void* base = ::mmap(nullptr, sizeof(apm44::ShmRingHeader), PROT_READ | PROT_WRITE,
                      MAP_SHARED, fd, 0);
  if (base == MAP_FAILED) {
    ::close(fd);
    return false;
  }
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  std::memset(header->producer_build_id, 0, apm44::kShmBuildIdBytes);
  std::strncpy(header->producer_build_id, buildId, apm44::kShmBuildIdBytes - 1);
  ::munmap(base, sizeof(apm44::ShmRingHeader));
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

TEST_CASE("remapped feed drains frames from the recreated ring", "[shm_stale_recovery]") {
  const std::string ringName = TestRingName('d');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(producer.create(512));

  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::Remapped);
  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::Ok);

  constexpr std::size_t kFrames = 64;
  std::vector<float> ramp(kFrames * 2);
  for (std::size_t i = 0; i < kFrames; ++i) {
    ramp[2 * i] = static_cast<float>(i) * 0.01f;
    ramp[2 * i + 1] = -(static_cast<float>(i) * 0.01f) - 0.5f;
  }
  REQUIRE(producer.pushInterleaved(ramp.data(), kFrames) == kFrames);

  apm44::PlanarRingBuffer planar;
  planar.prepare(256);
  REQUIRE(feed.drainTo(planar, kFrames) == kFrames);

  std::vector<float> left(kFrames);
  std::vector<float> right(kFrames);
  float* channels[2] = {left.data(), right.data()};
  REQUIRE(planar.pop(channels, kFrames) == kFrames);
  for (std::size_t i = 0; i < kFrames; ++i) {
    CHECK(left[i] == ramp[2 * i]);
    CHECK(right[i] == ramp[2 * i + 1]);
  }

  feed.markReady();
  REQUIRE(producer.daemonReady());

  feed.close();
  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("pollStaleRing exits when the ring is unlinked and not recreated",
          "[shm_stale_recovery]") {
  const std::string ringName = TestRingName('e');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  producer.close();
  UnlinkRing(ringName);

  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::MustExit);
  REQUIRE_FALSE(feed.isOpen());
  REQUIRE(feed.lastOpenErrorCode() == apm44::ShmRingErrorCode::OpenFailed);

  feed.close();
  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("pollStaleRing exits when the ring is recreated by a different driver build",
          "[shm_stale_recovery]") {
  const std::string ringName = TestRingName('f');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::VirtualDeviceFeed feed(ringName);
  REQUIRE(feed.open());

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(producer.create(512));
  REQUIRE(OverwriteProducerBuildId(ringName, "other-build"));

  // Decided behavior (T9, 2026-09-30): a mid-run build mismatch exits 42, not
  // 44. It usually means an update is in progress, and the app's retries pick
  // up the new helper; 44 would wrongly tell the user to reload the driver.
  // Prepare-time mismatch still exits 44 (ExitCodeForPrepareFailure).
  REQUIRE(feed.pollStaleRing() == apm44::StaleRingPollResult::MustExit);
  REQUIRE_FALSE(feed.isOpen());
  REQUIRE(feed.lastOpenErrorCode() == apm44::ShmRingErrorCode::ProducerBuildMismatch);

  feed.close();
  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("PlanStaleRingRecovery keeps output stopped once it decides to exit",
          "[shm_stale_recovery]") {
  using apm44::PlanStaleRingRecovery;
  using apm44::StaleRingPollResult;
  using apm44::VirtualFeedStaleAction;

  struct Row {
    StaleRingPollResult pollResult;
    bool epochResetOk;
    VirtualFeedStaleAction action;
    bool restartOutput;
  };
  const Row rows[] = {
      {StaleRingPollResult::Ok, true, VirtualFeedStaleAction::None, true},
      {StaleRingPollResult::Ok, false, VirtualFeedStaleAction::None, true},
      {StaleRingPollResult::Remapped, true, VirtualFeedStaleAction::StopForRemap, true},
      {StaleRingPollResult::Remapped, false, VirtualFeedStaleAction::StopForExit, false},
      {StaleRingPollResult::MustExit, true, VirtualFeedStaleAction::StopForExit, false},
      {StaleRingPollResult::MustExit, false, VirtualFeedStaleAction::StopForExit, false},
  };

  for (const Row& row : rows) {
    CAPTURE(static_cast<int>(row.pollResult), row.epochResetOk);
    const apm44::StaleRingRecoveryPlan plan =
        PlanStaleRingRecovery(row.pollResult, row.epochResetOk);
    CHECK(plan.action == row.action);
    CHECK(plan.restartOutput == row.restartOutput);
  }
}
