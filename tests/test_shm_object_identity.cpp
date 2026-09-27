#include "apm44/MmapShmRing.h"
#include "apm44/ShmObjectIdentity.h"

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

}  // namespace

TEST_CASE("ShmObjectIdentityChanged false for unchanged object", "[shm_object_identity]") {
  const std::string ringName = TestRingName('c');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::ShmObjectIdentity first;
  apm44::ShmObjectIdentity second;
  REQUIRE(apm44::StatNamedShmObject(ringName, first));
  REQUIRE(apm44::StatNamedShmObject(ringName, second));
  REQUIRE_FALSE(apm44::ShmObjectIdentityChanged(first, second));

  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("ShmObjectIdentityChanged treats a size change as stale", "[shm_object_identity][SHM-03]") {
  // Pure-function rows built from hand-made identities (no shm
  // needed); see ShmObjectIdentityChanged for the exact rules.
  auto makeIdentity = [](dev_t dev, ino_t ino, std::size_t size, uint32_t gen) {
    apm44::ShmObjectIdentity identity;
    identity.st_dev = dev;
    identity.st_ino = ino;
    identity.size = size;
    identity.driver_generation = gen;
    identity.valid = true;
    identity.has_generation = true;
    return identity;
  };
  // Same dev/ino/gen but different non-zero size -> true (SHM-03).
  REQUIRE(apm44::ShmObjectIdentityChanged(makeIdentity(1, 2, 100, 7),
                                          makeIdentity(1, 2, 200, 7)));
  // Size 0 on either side disables the size branch -> false.
  REQUIRE_FALSE(apm44::ShmObjectIdentityChanged(makeIdentity(1, 2, 0, 7),
                                                makeIdentity(1, 2, 200, 7)));
  REQUIRE_FALSE(apm44::ShmObjectIdentityChanged(makeIdentity(1, 2, 100, 7),
                                                makeIdentity(1, 2, 0, 7)));
  // Identical identities -> false.
  REQUIRE_FALSE(apm44::ShmObjectIdentityChanged(makeIdentity(1, 2, 100, 7),
                                                makeIdentity(1, 2, 100, 7)));
}

TEST_CASE("Consumer mappedObjectIdentity matches StatNamedShmObject", "[shm_object_identity]") {
  const std::string ringName = TestRingName('d');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  apm44::ShmObjectIdentity statIdentity;
  REQUIRE(apm44::StatNamedShmObject(ringName, statIdentity));
  // Carried over from the removed `StatNamedShmObject returns valid
  // identity after producer create`: the stat identity itself is valid.
  REQUIRE(statIdentity.valid);

  const apm44::ShmObjectIdentity& mapped = consumer.mappedObjectIdentity();
  REQUIRE(mapped.valid);
  REQUIRE(mapped.st_dev == statIdentity.st_dev);
  REQUIRE(mapped.st_ino == statIdentity.st_ino);

  producer.close();
  consumer.close();
  UnlinkRing(ringName);
}

TEST_CASE("isMappedObjectStale after producer recreates ring", "[shm_object_identity]") {
  const std::string ringName = TestRingName('e');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE_FALSE(consumer.isMappedObjectStale());
  // Carried over from the removed `ShmObjectIdentityChanged after
  // recreate with same name`: the pre-recreate mapped identity is
  // valid and differs from the post-recreate stat identity.
  const apm44::ShmObjectIdentity before = consumer.mappedObjectIdentity();
  REQUIRE(before.valid);

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(producer.create(512));

  apm44::ShmObjectIdentity after;
  REQUIRE(apm44::StatNamedShmObject(ringName, after));
  REQUIRE(apm44::ShmObjectIdentityChanged(before, after));
  REQUIRE(consumer.isMappedObjectStale());

  producer.close();
  consumer.close();
  UnlinkRing(ringName);
}

TEST_CASE("isMappedObjectStale when driver_generation advances", "[shm_object_identity]") {
  const std::string ringName = TestRingName('f');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE_FALSE(consumer.isMappedObjectStale());

  producer.header()->driver_generation.fetch_add(1, std::memory_order_relaxed);
  REQUIRE(consumer.isMappedObjectStale());

  producer.close();
  consumer.close();
  UnlinkRing(ringName);
}
