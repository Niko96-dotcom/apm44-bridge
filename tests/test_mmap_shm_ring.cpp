#include "apm44/MmapShmRing.h"
#include "apm44/PlanarRingBuffer.h"

#include <catch2/catch_approx.hpp>
#include <catch2/catch_test_macros.hpp>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cmath>
#include <string>
#include <vector>

namespace {

std::string TestRingName(char suffix) {
  return "/apm44t" + std::to_string(static_cast<long long>(getpid())) + suffix;
}

}  // namespace

TEST_CASE("MmapShmRing producer consumer round trip", "[mmap_shm_ring]") {
  const std::string ringName = TestRingName('r');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(1024));

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE(consumer.header()->version == apm44::kShmVersion);
  REQUIRE(std::string(consumer.header()->producer_build_id) == apm44::kBuildId);

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
  shm_unlink(ringName.c_str());
}

TEST_CASE("MmapShmRing reports invalid shm header", "[mmap_shm_ring]") {
  const std::string ringName = TestRingName('i');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));
  producer.header()->version = 99;

  apm44::MmapShmRing consumer(ringName);
  REQUIRE_FALSE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE(consumer.lastErrorCode() == apm44::ShmRingErrorCode::InvalidHeader);
  REQUIRE(consumer.lastError().find("expected_version") != std::string::npos);

  producer.close();
  consumer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("MmapShmRing popToPlanar feeds planar buffer", "[mmap_shm_ring]") {
  const std::string ringName = TestRingName('p');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer(ringName);
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
  shm_unlink(ringName.c_str());
}

TEST_CASE("MmapShmRing fails closed on impossible shared-memory fill counts",
          "[mmap_shm_ring][integrity]") {
  const std::string ringName = TestRingName('c');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(8));

  producer.header()->write_index.store(100, std::memory_order_relaxed);
  producer.header()->read_index.store(0, std::memory_order_relaxed);

  float interleaved[16] = {};
  REQUIRE(producer.pushInterleaved(interleaved, 1) == 0);
  REQUIRE(producer.popInterleaved(interleaved, 16) == 0);

  producer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("Consumer repairs corrupt indices by discarding questionable audio",
          "[mmap_shm_ring][integrity]") {
  const std::string ringName = TestRingName('x');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(16));
  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  const uint64_t resetsBefore = consumer.producerDiagnostics().consumerResets;
  producer.header()->write_index.store(100, std::memory_order_relaxed);
  producer.header()->read_index.store(0, std::memory_order_relaxed);
  float output[2] = {};
  REQUIRE(consumer.popInterleaved(output, 1) == 0);
  REQUIRE(producer.header()->read_index.load(std::memory_order_acquire) == 100);
  REQUIRE(consumer.producerDiagnostics().consumerResets == resetsBefore + 1);

  const float fresh[2] = {0.25f, -0.25f};
  REQUIRE(producer.pushInterleaved(fresh, 1) == 1);
  REQUIRE(consumer.popInterleaved(output, 1) == 1);
  REQUIRE(output[0] == Catch::Approx(fresh[0]));
  REQUIRE(output[1] == Catch::Approx(fresh[1]));

  consumer.close();
  producer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("Consumer refuses reads after ownership token tampering",
          "[mmap_shm_ring][integrity]") {
  const std::string ringName = TestRingName('t');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(16));
  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  const uint64_t ownedToken =
      producer.header()->consumer_token.load(std::memory_order_acquire);
  const float input[2] = {0.5f, -0.5f};
  float output[2] = {};
  REQUIRE(producer.pushInterleaved(input, 1) == 1);
  producer.header()->consumer_token.store(ownedToken + 1, std::memory_order_release);
  REQUIRE(consumer.popInterleaved(output, 1) == 0);

  producer.header()->consumer_token.store(ownedToken, std::memory_order_release);
  consumer.close();
  producer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("Consumer attach discards prior session audio", "[mmap_shm_ring][session]") {
  const std::string ringName = TestRingName('s');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(16));

  std::vector<float> signalA(8 * 2, 0.25f);
  REQUIRE(producer.pushInterleaved(signalA.data(), 8) == 8);

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE(consumer.consumerEpoch() == 1);
  std::vector<float> out(8 * 2);
  REQUIRE(consumer.popInterleaved(out.data(), 8) == 0);

  consumer.setDaemonReady();
  std::vector<float> signalB(4 * 2, -0.75f);
  REQUIRE(producer.pushInterleaved(signalB.data(), 4) == 4);
  REQUIRE(consumer.popInterleaved(out.data(), 4) == 4);
  for (std::size_t i = 0; i < 4 * 2; ++i) {
    REQUIRE(out[i] == Catch::Approx(signalB[i]));
  }

  consumer.close();
  REQUIRE_FALSE(producer.daemonReady());
  REQUIRE(producer.header()->consumer_pid.load(std::memory_order_acquire) == 0);

  REQUIRE(producer.pushInterleaved(signalA.data(), 8) == 8);
  apm44::MmapShmRing reconnected(ringName);
  REQUIRE(reconnected.open(apm44::ShmRingRole::Consumer));
  REQUIRE(reconnected.consumerEpoch() == 2);
  REQUIRE(reconnected.popInterleaved(out.data(), 8) == 0);
  reconnected.setDaemonReady();
  REQUIRE(producer.pushInterleaved(signalB.data(), 4) == 4);
  REQUIRE(reconnected.popInterleaved(out.data(), 4) == 4);
  for (std::size_t i = 0; i < 4 * 2; ++i) {
    REQUIRE(out[i] == Catch::Approx(signalB[i]));
  }

  reconnected.close();
  producer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("Only one live shm consumer can claim the ring", "[mmap_shm_ring][session]") {
  const std::string ringName = TestRingName('o');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(16));

  apm44::MmapShmRing first(ringName);
  apm44::MmapShmRing second(ringName);
  REQUIRE(first.open(apm44::ShmRingRole::Consumer));
  REQUIRE_FALSE(second.open(apm44::ShmRingRole::Consumer));
  REQUIRE(second.lastErrorCode() == apm44::ShmRingErrorCode::ConsumerBusy);

  first.close();
  REQUIRE(second.open(apm44::ShmRingRole::Consumer));
  second.close();
  producer.close();
  shm_unlink(ringName.c_str());
}

TEST_CASE("MmapShmRing closed ring returns zero safely", "[mmap_shm_ring]") {
  apm44::MmapShmRing ring;
  REQUIRE_FALSE(ring.isMapped());

  float interleaved[4] = {1.0f, 2.0f, 3.0f, 4.0f};
  float out0[4] = {};
  float out1[4] = {};
  float* planar[2] = {out0, out1};

  REQUIRE(ring.pushInterleaved(interleaved, 2) == 0);
  REQUIRE(ring.popInterleaved(interleaved, 2) == 0);
  REQUIRE(ring.popToPlanar(planar, 2) == 0);
  ring.setDaemonReady();
}
