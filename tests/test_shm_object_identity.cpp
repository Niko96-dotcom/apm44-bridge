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

TEST_CASE("StatNamedShmObject returns valid identity after producer create",
          "[shm_object_identity]") {
  const std::string ringName = TestRingName('a');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::ShmObjectIdentity identity;
  REQUIRE(apm44::StatNamedShmObject(ringName, identity));
  REQUIRE(identity.valid);

  apm44::ShmObjectIdentity mapped = producer.mappedObjectIdentity();
  REQUIRE(mapped.valid);
  REQUIRE(mapped.st_dev == identity.st_dev);
  REQUIRE(mapped.st_ino == identity.st_ino);

  producer.close();
  UnlinkRing(ringName);
}

TEST_CASE("ShmObjectIdentityChanged after recreate with same name", "[shm_object_identity]") {
  const std::string ringName = TestRingName('b');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  const apm44::ShmObjectIdentity before = consumer.mappedObjectIdentity();
  REQUIRE(before.valid);

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(producer.create(512));

  apm44::ShmObjectIdentity after;
  REQUIRE(apm44::StatNamedShmObject(ringName, after));
  REQUIRE(apm44::ShmObjectIdentityChanged(before, after));

  producer.close();
  consumer.close();
  UnlinkRing(ringName);
}

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

TEST_CASE("Consumer mappedObjectIdentity matches StatNamedShmObject", "[shm_object_identity]") {
  const std::string ringName = TestRingName('d');
  apm44::MmapShmRing producer(ringName);
  REQUIRE(producer.create(512));

  apm44::MmapShmRing consumer(ringName);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));

  apm44::ShmObjectIdentity statIdentity;
  REQUIRE(apm44::StatNamedShmObject(ringName, statIdentity));

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

  producer.close();
  UnlinkRing(ringName);
  REQUIRE(producer.create(512));

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
