// SHM-01..SHM-04 regression tests for the size validation, capacity
// validation, bounded build-ID rendering, and live size-change
// detection. All tests use isolated shm names; no test references
// `/apm44_bridge_ring`.
//
// Note on platform defenses: macOS rounds shm object sizes to a
// full page (typically 16 KiB) and `ftruncate` cannot shrink or
// grow the reported `st_size` once the page is allocated. The
// defensive `HeaderTruncated` (SHM-01) check cannot be reached with a real
// object on this platform; its size boundaries are covered by the
// `ClassifyShmObjectSize` table below. SHM-03's size
// branch is proved functionally in
// tests/test_shm_object_identity.cpp. SHM-02 and SHM-04 are
// functionally tested below.

#include "apm44/MmapShmRing.h"
#include "apm44/ShmRingLayout.h"

#include <catch2/catch_test_macros.hpp>

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

std::string IsolatedName(const char* tag) {
  // macOS PSHMNAMLEN is 31, including the leading slash. Keep names short.
  return std::string("/v") + std::to_string(static_cast<long long>(getpid())) + "_" + tag;
}

// Create a shm object with the given byte size, returning its fd.
// The fd is leaked intentionally — the test cleans it up via
// `::shm_unlink(name)` after closing it.
int CreateRawShmObject(const std::string& name, std::size_t bytes) {
  ::shm_unlink(name.c_str());
  const int fd = ::shm_open(name.c_str(), O_CREAT | O_RDWR | O_EXCL, 0600);
  if (fd < 0) {
    return -1;
  }
  if (::ftruncate(fd, static_cast<off_t>(bytes)) != 0) {
    ::close(fd);
    ::shm_unlink(name.c_str());
    return -1;
  }
  return fd;
}

void CleanupShmObject(const std::string& name) {
  ::shm_unlink(name.c_str());
}

void WriteValidHeader(void* base, uint32_t capacityFrames) {
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  header->magic = apm44::kShmMagic;
  header->version = apm44::kShmVersion;
  header->capacity_frames = capacityFrames;
  header->sample_rate = apm44::kShmSampleRate;
  header->channels = apm44::kShmChannels;
  header->header_bytes = static_cast<uint32_t>(sizeof(apm44::ShmRingHeader));
  std::strncpy(header->producer_build_id, apm44::kBuildId, apm44::kShmBuildIdBytes - 1);
}

}  // namespace

TEST_CASE("OpenRejectsValidHeaderWithHugeCapacity", "[mmap_shm][validation][SHM-02]") {
  const std::string name = IsolatedName("huge_cap");
  // Create a shm object sized for capacity_frames = 64, then write
  // a syntactically valid header that claims 1,000,000 frames. The
  // declared total size is far larger than the mapped object, so
  // the SHM-02 capacity-vs-mapped check must fire.
  const std::size_t smallSize = apm44::ShmTotalSize(64);
  const int fd = CreateRawShmObject(name, smallSize);
  REQUIRE(fd >= 0);

  // Determine the actual mapped size the kernel gave us (it rounds
  // up to a full page on macOS). We use `smallSize` for the
  // mmap write window, but the open() path uses fstat.
  struct stat st {};
  REQUIRE(::fstat(fd, &st) == 0);
  const std::size_t mappedSize = static_cast<std::size_t>(st.st_size);
  REQUIRE(mappedSize >= sizeof(apm44::ShmRingHeader));
  // The declared total (1,000,000 frames) must exceed the actual
  // mapped size for SHM-02 to fire.
  const std::size_t declaredFrames = 1'000'000;
  const std::size_t declaredTotal = apm44::ShmTotalSize(declaredFrames);
  REQUIRE(declaredTotal > mappedSize);

  void* base = ::mmap(nullptr, mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  REQUIRE(base != MAP_FAILED);
  std::memset(base, 0, mappedSize);
  WriteValidHeader(base, static_cast<uint32_t>(declaredFrames));
  ::munmap(base, mappedSize);
  ::close(fd);

  apm44::MmapShmRing ring(name);
  REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
  REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::CapacityExceedsObject);
  // Diagnostic must mention the declared capacity (in frames) so
  // the operator can see the mismatch.
  const std::string err = ring.lastError();
  REQUIRE(err.find(std::to_string(declaredFrames)) != std::string::npos);

  CleanupShmObject(name);
}

TEST_CASE("ClassifyShmObjectSize separates empty, truncated and header-sized objects",
          "[mmap_shm][validation][SHM-01]") {
  // This table proves the size boundaries open() relies on. It does not prove
  // open() calls the helper before touching the header; that ordering rests on
  // review, because macOS page rounding stops a real truncated object from
  // reaching open().
  constexpr std::int64_t kHeader = static_cast<std::int64_t>(sizeof(apm44::ShmRingHeader));
  using apm44::ClassifyShmObjectSize;
  using apm44::ShmObjectSizeClass;

  CHECK(ClassifyShmObjectSize(-1) == ShmObjectSizeClass::Empty);
  CHECK(ClassifyShmObjectSize(0) == ShmObjectSizeClass::Empty);
  CHECK(ClassifyShmObjectSize(1) == ShmObjectSizeClass::HeaderTruncated);
  CHECK(ClassifyShmObjectSize(kHeader - 1) == ShmObjectSizeClass::HeaderTruncated);
  CHECK(ClassifyShmObjectSize(kHeader) == ShmObjectSizeClass::HeaderSized);
  CHECK(ClassifyShmObjectSize(kHeader + 1) == ShmObjectSizeClass::HeaderSized);
  CHECK(ClassifyShmObjectSize(static_cast<std::int64_t>(apm44::ShmTotalSize(64))) ==
        ShmObjectSizeClass::HeaderSized);
}

TEST_CASE("HeaderMismatchDiagnosticHandlesUnterminatedBuildId",
          "[mmap_shm][validation][SHM-04]") {
  const std::string name = IsolatedName("unterm");
  // Create a properly sized object and write a header whose magic /
  // version / channels / capacity all pass ValidateShmHeader, but
  // whose `producer_build_id` is filled with 'X' for the full
  // 64 bytes — no null terminator.
  const std::size_t totalSize = apm44::ShmTotalSize(64);
  const int fd = CreateRawShmObject(name, totalSize);
  REQUIRE(fd >= 0);

  void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  REQUIRE(base != MAP_FAILED);
  std::memset(base, 0, totalSize);
  WriteValidHeader(base, 64);
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  header->magic = apm44::kShmMagic + 1;  // Force a magic mismatch.
  std::memset(header->producer_build_id, 'X', apm44::kShmBuildIdBytes);
  ::munmap(base, totalSize);
  ::close(fd);

  apm44::MmapShmRing ring(name);
  REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
  // Header is rejected for the magic mismatch; the diagnostic must
  // either substitute the "<unterminated>" sentinel for the build
  // ID, or stop at the first embedded null. It must NOT include
  // arbitrary bytes past the producer_build_id field (i.e. it must
  // not read past the field boundary).
  const std::string err = ring.lastError();
  REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::InvalidHeader);
  // Either sentinel present, or no more than kShmBuildIdBytes of
  // build-id content in the diagnostic.
  const bool hasSentinel = err.find("<unterminated>") != std::string::npos;
  const bool hasX = err.find("producer_build_id='") != std::string::npos;
  REQUIRE((hasSentinel || hasX));
  if (hasX && !hasSentinel) {
    // Count the number of 'X' bytes between the quotes — it must
    // not exceed the field size. We accept any value from 0 to
    // kShmBuildIdBytes (the implementation may stop at an
    // embedded null), but it must not be more.
    const auto start = err.find("producer_build_id='") + std::strlen("producer_build_id='");
    const auto end = err.find("'", start);
    REQUIRE(end != std::string::npos);
    const std::size_t n = end - start;
    REQUIRE(n <= apm44::kShmBuildIdBytes);
  }

  CleanupShmObject(name);
}

TEST_CASE("Open rejects single-field header corruption", "[mmap_shm][validation]") {
  // Folded from `OpenRejectsBadMagicAsInvalidHeader`,
  // `OpenRejectsWrongChannelsAsInvalidHeader`, and
  // `OpenRejectsMismatchedSampleRate`: each row mutates exactly one
  // header field and asserts the same per-case expectations the
  // original made (open returns false, InvalidHeader; the sample-rate
  // row additionally checks the expected_sample_rate diagnostic).
  struct Row {
    const char* tag;
    const char* nameTag;
    void (*mutate)(apm44::ShmRingHeader*);
    bool checkRateText;
  };
  const Row rows[] = {
      {"magic", "mag",
       [](apm44::ShmRingHeader* header) { header->magic = 0xDEADBEEFu; }, false},
      {"channels", "ch",
       [](apm44::ShmRingHeader* header) {
         header->channels = apm44::kShmChannels + 1;
       },
       false},
      {"sample_rate", "rate",
       [](apm44::ShmRingHeader* header) { header->sample_rate = 48000; }, true},
  };
  for (const Row& row : rows) {
    DYNAMIC_SECTION("field=" << row.tag) {
      INFO("mutated field=" << row.tag);
      const std::string name = IsolatedName(row.nameTag);
      const std::size_t totalSize = apm44::ShmTotalSize(64);
      const int fd = CreateRawShmObject(name, totalSize);
      REQUIRE(fd >= 0);

      void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
      REQUIRE(base != MAP_FAILED);
      std::memset(base, 0, totalSize);
      WriteValidHeader(base, 64);
      auto* header = static_cast<apm44::ShmRingHeader*>(base);
      row.mutate(header);
      ::munmap(base, totalSize);
      ::close(fd);

      apm44::MmapShmRing ring(name);
      REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
      REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::InvalidHeader);
      if (row.checkRateText) {
        REQUIRE(ring.lastError().find("expected_sample_rate=44100") != std::string::npos);
      }

      CleanupShmObject(name);
    }
  }
}

TEST_CASE("OpenRejectsMismatchedProducerBuildId", "[mmap_shm][validation][SHM-02]") {
  // Folded from `ObserverRejectsMismatchedProducerBuildId`: the same
  // stale-build-id check runs for both Consumer and Observer roles.
  const apm44::ShmRingRole roles[] = {apm44::ShmRingRole::Consumer,
                                      apm44::ShmRingRole::Observer};
  for (const apm44::ShmRingRole role : roles) {
    DYNAMIC_SECTION("role=" << (role == apm44::ShmRingRole::Consumer ? "consumer" : "observer")) {
      const std::string name = IsolatedName(role == apm44::ShmRingRole::Consumer ? "build" : "obsb");
      const std::size_t totalSize = apm44::ShmTotalSize(64);
      const int fd = CreateRawShmObject(name, totalSize);
      REQUIRE(fd >= 0);

      void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
      REQUIRE(base != MAP_FAILED);
      std::memset(base, 0, totalSize);
      WriteValidHeader(base, 64);
      auto* header = static_cast<apm44::ShmRingHeader*>(base);
      std::memset(header->producer_build_id, 0, apm44::kShmBuildIdBytes);
      std::strncpy(header->producer_build_id, "stale-build", apm44::kShmBuildIdBytes - 1);
      ::munmap(base, totalSize);
      ::close(fd);

      apm44::MmapShmRing ring(name);
      INFO("role=" << (role == apm44::ShmRingRole::Consumer ? "consumer" : "observer"));
      REQUIRE_FALSE(ring.open(role));
      REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::ProducerBuildMismatch);
      REQUIRE(ring.lastError().find("producer_build_id='stale-build'") != std::string::npos);
      REQUIRE(ring.lastError().find("expected_consumer_build_id='") != std::string::npos);

      CleanupShmObject(name);
    }
  }
}

TEST_CASE("OpenRejectsZeroVersionAsInvalidHeader", "[mmap_shm][validation]") {
  // A half-published header (producer mid-create()) shows valid magic
  // with version==0; that transient must stay InvalidHeader,
  // never ProducerBuildMismatch (sticky exit 44).
  const std::string name = IsolatedName("ver0");
  const std::size_t totalSize = apm44::ShmTotalSize(64);
  const int fd = CreateRawShmObject(name, totalSize);
  REQUIRE(fd >= 0);

  void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  REQUIRE(base != MAP_FAILED);
  std::memset(base, 0, totalSize);
  WriteValidHeader(base, 64);
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  header->version = 0;
  ::munmap(base, totalSize);
  ::close(fd);

  apm44::MmapShmRing ring(name);
  REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
  REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::InvalidHeader);

  CleanupShmObject(name);
}

TEST_CASE("OpenRejectsZeroedBuildIdAsInvalidHeader", "[mmap_shm][validation]") {
  // Valid magic+version with a zeroed build id is a half-published
  // header, not a stale driver: InvalidHeader, not ProducerBuildMismatch.
  const std::string name = IsolatedName("nobuild");
  const std::size_t totalSize = apm44::ShmTotalSize(64);
  const int fd = CreateRawShmObject(name, totalSize);
  REQUIRE(fd >= 0);

  void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  REQUIRE(base != MAP_FAILED);
  std::memset(base, 0, totalSize);
  WriteValidHeader(base, 64);
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  std::memset(header->producer_build_id, 0, apm44::kShmBuildIdBytes);
  ::munmap(base, totalSize);
  ::close(fd);

  apm44::MmapShmRing ring(name);
  REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
  REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::InvalidHeader);

  CleanupShmObject(name);
}

TEST_CASE("OpenRejectsUnterminatedBuildIdAsInvalidHeader", "[mmap_shm][validation]") {
  // Valid magic+version with a build id that fills all 64 bytes (no NUL
  // terminator) is a partially-copied build id: InvalidHeader, not
  // ProducerBuildMismatch.
  const std::string name = IsolatedName("rawbuild");
  const std::size_t totalSize = apm44::ShmTotalSize(64);
  const int fd = CreateRawShmObject(name, totalSize);
  REQUIRE(fd >= 0);

  void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  REQUIRE(base != MAP_FAILED);
  std::memset(base, 0, totalSize);
  WriteValidHeader(base, 64);
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  std::memset(header->producer_build_id, 'X', apm44::kShmBuildIdBytes);
  ::munmap(base, totalSize);
  ::close(fd);

  apm44::MmapShmRing ring(name);
  REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
  REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::InvalidHeader);

  CleanupShmObject(name);
}

TEST_CASE("OpenRejectsVersionMismatchAsBuildMismatch", "[mmap_shm][validation]") {
  const std::string name = IsolatedName("ver");
  const std::size_t totalSize = apm44::ShmTotalSize(64);
  const int fd = CreateRawShmObject(name, totalSize);
  REQUIRE(fd >= 0);

  void* base = ::mmap(nullptr, totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  REQUIRE(base != MAP_FAILED);
  std::memset(base, 0, totalSize);
  WriteValidHeader(base, 64);
  auto* header = static_cast<apm44::ShmRingHeader*>(base);
  header->version = apm44::kShmVersion - 1;
  ::munmap(base, totalSize);
  ::close(fd);

  apm44::MmapShmRing ring(name);
  REQUIRE_FALSE(ring.open(apm44::ShmRingRole::Consumer));
  REQUIRE(ring.lastErrorCode() == apm44::ShmRingErrorCode::ProducerBuildMismatch);
  REQUIRE(ring.lastError().find("expected_version") != std::string::npos);

  CleanupShmObject(name);
}

TEST_CASE("OpenAcceptsCorrectlySizedObject", "[mmap_shm][validation]") {
  // Sanity baseline: a normally created object must still open and
  // round-trip a few frames after the new validation is in place.
  const std::string name = IsolatedName("happy");
  apm44::MmapShmRing producer(name);
  REQUIRE(producer.create(128));

  apm44::MmapShmRing consumer(name);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE(consumer.isMapped());

  std::vector<float> interleaved(2 * 8);
  for (std::size_t i = 0; i < 8; ++i) {
    interleaved[i * 2 + 0] = static_cast<float>(i);
    interleaved[i * 2 + 1] = -static_cast<float>(i);
  }
  REQUIRE(producer.pushInterleaved(interleaved.data(), 8) == 8);

  std::vector<float> out(2 * 8);
  REQUIRE(consumer.popInterleaved(out.data(), 8) == 8);

  producer.close();
  consumer.close();
  CleanupShmObject(name);
}

TEST_CASE("MmapShmRingUsesCachedCapacityAfterHeaderMutation",
          "[mmap_shm][validation][hardening]") {
  const std::string name = IsolatedName("hotcap");
  apm44::MmapShmRing producer(name);
  REQUIRE(producer.create(64));

  apm44::MmapShmRing consumer(name);
  REQUIRE(consumer.open(apm44::ShmRingRole::Consumer));
  REQUIRE(producer.header() != nullptr);
  REQUIRE(consumer.header() != nullptr);

  producer.header()->capacity_frames = 0;

  std::vector<float> interleaved(2 * 8);
  for (std::size_t i = 0; i < 8; ++i) {
    interleaved[i * 2 + 0] = static_cast<float>(i + 1);
    interleaved[i * 2 + 1] = -static_cast<float>(i + 1);
  }
  REQUIRE(producer.pushInterleaved(interleaved.data(), 8) == 8);

  std::vector<float> out(2 * 8);
  REQUIRE(consumer.popInterleaved(out.data(), 8) == 8);
  REQUIRE(out == interleaved);

  producer.header()->capacity_frames = 1'000'000;
  REQUIRE(producer.pushInterleaved(interleaved.data(), 8) == 8);
  std::vector<float> left(8);
  std::vector<float> right(8);
  float* planar[2] = {left.data(), right.data()};
  REQUIRE(consumer.popToPlanar(planar, 8) == 8);
  for (std::size_t i = 0; i < 8; ++i) {
    REQUIRE(left[i] == interleaved[i * 2 + 0]);
    REQUIRE(right[i] == interleaved[i * 2 + 1]);
  }

  producer.close();
  consumer.close();
  CleanupShmObject(name);
}
