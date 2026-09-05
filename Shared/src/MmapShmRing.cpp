#include "apm44/MmapShmRing.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <sstream>
#include <signal.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <utility>
#include <unistd.h>

namespace apm44 {

namespace {

constexpr int kMapProt = PROT_READ | PROT_WRITE;

std::atomic<uint32_t> gNextShmDriverGeneration{0};
std::atomic<uint64_t> gNextConsumerToken{0};

bool IsPermissionErrno(int err) { return err == EACCES || err == EPERM; }

bool ProcessIsAlive(uint32_t pid) {
  if (pid == 0) {
    return false;
  }
  if (::kill(static_cast<pid_t>(pid), 0) == 0) {
    return true;
  }
  return errno == EPERM;
}

void CaptureMappedIdentity(int fd, ShmObjectIdentity& identity,
                           const ShmRingHeader* header) {
  identity = {};
  if (header != nullptr) {
    identity.driver_generation = header->driver_generation.load(std::memory_order_relaxed);
    identity.has_generation = true;
  }
  struct stat st {};
  if (fd >= 0 && ::fstat(fd, &st) == 0) {
    identity.st_dev = st.st_dev;
    identity.st_ino = st.st_ino;
    identity.size = static_cast<std::size_t>(st.st_size);
    identity.valid = true;
  }
}

void CopyBuildId(char (&dst)[kShmBuildIdBytes]) {
  std::memset(dst, 0, sizeof(dst));
  std::strncpy(dst, kBuildId, sizeof(dst) - 1);
}

std::string DescribeHeaderMismatch(const ShmRingHeader& header) {
  std::ostringstream out;
  out << "invalid shm ring header"
      << " magic=0x" << std::hex << header.magic << std::dec
      << " version=" << header.version
      << " expected_version=" << kShmVersion
      << " header_bytes=" << header.header_bytes
      << " expected_header_bytes>=" << sizeof(ShmRingHeader)
      << " sample_rate=" << header.sample_rate
      << " expected_sample_rate=" << kShmSampleRate
      << " channels=" << header.channels
      << " expected_channels=" << kShmChannels
      << " producer_build_id='" << RenderShmBuildId(header.producer_build_id) << "'"
      << " expected_consumer_build_id='" << RenderShmBuildId(kBuildId) << "'";
  return out.str();
}

}  // namespace

MmapShmRing::MmapShmRing(std::string name) : name_(std::move(name)) {}

MmapShmRing::~MmapShmRing() { close(); }

bool MmapShmRing::create(uint32_t capacityFrames) {
  close();
  clearError();
  role_ = ShmRingRole::Producer;

  const std::size_t totalSize = ShmTotalSize(capacityFrames);
  // Driver runs in coreaudiod; daemon runs as the logged-in user — world rw required.
  ::shm_unlink(name_.c_str());
  fd_ = ::shm_open(name_.c_str(), O_CREAT | O_RDWR | O_EXCL, 0666);
  if (fd_ < 0 && errno == EEXIST) {
    fd_ = ::shm_open(name_.c_str(), O_RDWR, 0666);
    if (fd_ >= 0) {
      ::fchmod(fd_, 0666);
    }
  }
  if (fd_ < 0) {
    const int err = errno;
    recordErrno(IsPermissionErrno(err) ? ShmRingErrorCode::PermissionFailed
                                       : ShmRingErrorCode::CreateFailed,
                "shm_open(create)", err);
    return false;
  }
  if (::fchmod(fd_, 0666) != 0) {
    // Continue; mode at create time should already allow daemon access.
  }
  if (::ftruncate(fd_, static_cast<off_t>(totalSize)) != 0) {
    const int err = errno;
    close();
    recordErrno(ShmRingErrorCode::TruncateFailed, "ftruncate", err);
    return false;
  }

  base_ = ::mmap(nullptr, totalSize, kMapProt, MAP_SHARED, fd_, 0);
  if (base_ == MAP_FAILED) {
    const int err = errno;
    base_ = nullptr;
    close();
    recordErrno(IsPermissionErrno(err) ? ShmRingErrorCode::PermissionFailed
                                       : ShmRingErrorCode::MapFailed,
                "mmap(create)", err);
    return false;
  }
  mappedSize_ = totalSize;
  header_ = static_cast<ShmRingHeader*>(base_);
  std::memset(base_, 0, totalSize);

  header_->magic = kShmMagic;
  header_->version = kShmVersion;
  header_->capacity_frames = capacityFrames;
  capacityFrames_ = capacityFrames;
  header_->sample_rate = kShmSampleRate;
  header_->channels = kShmChannels;
  header_->header_bytes = static_cast<uint32_t>(sizeof(ShmRingHeader));
  CopyBuildId(header_->producer_build_id);
  header_->write_index.store(0, std::memory_order_relaxed);
  header_->read_index.store(0, std::memory_order_relaxed);
  header_->daemon_ready.store(0, std::memory_order_relaxed);
  const uint32_t generation =
      gNextShmDriverGeneration.fetch_add(1, std::memory_order_relaxed) + 1;
  header_->driver_generation.store(generation, std::memory_order_relaxed);
  header_->producer_epoch.store(generation, std::memory_order_relaxed);
  CaptureMappedIdentity(fd_, mappedIdentity_, header_);
  return true;
}

bool MmapShmRing::open(ShmRingRole role) {
  close();
  clearError();
  role_ = role;

  fd_ = ::shm_open(name_.c_str(), O_RDWR, 0);
  if (fd_ < 0) {
    const int err = errno;
    recordErrno(IsPermissionErrno(err) ? ShmRingErrorCode::PermissionFailed
                                       : ShmRingErrorCode::OpenFailed,
                "shm_open(open)", err);
    return false;
  }

  struct stat st {};
  if (::fstat(fd_, &st) != 0 || st.st_size <= 0) {
    const int err = errno;
    const bool empty = st.st_size <= 0;
    close();
    if (empty) {
      recordError(ShmRingErrorCode::EmptyObject, "shm object exists but has zero size");
    } else {
      recordErrno(ShmRingErrorCode::StatFailed, "fstat", err);
    }
    return false;
  }
  // SHM-01: reject objects too small to contain a ShmRingHeader
  // BEFORE we map or read the header. The previous implementation
  // mapped the object and then dereferenced `header_`, which would
  // read past the end of a truncated object.
  if (static_cast<std::size_t>(st.st_size) < sizeof(ShmRingHeader)) {
    const std::string message = "shm object is smaller than ShmRingHeader: " +
                                std::to_string(st.st_size) + " bytes";
    close();
    recordError(ShmRingErrorCode::HeaderTruncated, message);
    return false;
  }
  mappedSize_ = static_cast<std::size_t>(st.st_size);
  base_ = ::mmap(nullptr, mappedSize_, kMapProt, MAP_SHARED, fd_, 0);
  if (base_ == MAP_FAILED) {
    const int err = errno;
    base_ = nullptr;
    close();
    recordErrno(IsPermissionErrno(err) ? ShmRingErrorCode::PermissionFailed
                                       : ShmRingErrorCode::MapFailed,
                "mmap(open)", err);
    return false;
  }
  header_ = static_cast<ShmRingHeader*>(base_);
  if (!ValidateShmHeader(*header_)) {
    const std::string message = DescribeHeaderMismatch(*header_);
    close();
    recordError(ShmRingErrorCode::InvalidHeader, message);
    return false;
  }
  // SHM-02: a syntactically valid header can still lie about its
  // capacity. The mapped object must be large enough to hold the
  // declared sample data plus the header. A producer that truncated
  // the object after writing a valid header would otherwise pass
  // the field-level validation and crash on the first push/pop.
  const std::size_t declaredTotal =
      ShmTotalSize(header_->capacity_frames);
  if (mappedSize_ < declaredTotal) {
    const std::string message =
        "shm object too small for declared capacity: mapped " +
        std::to_string(mappedSize_) + " bytes, header declares " +
        std::to_string(declaredTotal) + " bytes (capacity_frames=" +
        std::to_string(header_->capacity_frames) + ")";
    close();
    recordError(ShmRingErrorCode::CapacityExceedsObject, message);
    return false;
  }
  capacityFrames_ = header_->capacity_frames;
  CaptureMappedIdentity(fd_, mappedIdentity_, header_);
  if (role_ == ShmRingRole::Consumer && !claimConsumer()) {
    const uint32_t ownerPid = header_->consumer_pid.load(std::memory_order_acquire);
    close();
    recordError(ShmRingErrorCode::ConsumerBusy,
                "shm ring already has a live consumer pid=" + std::to_string(ownerPid));
    return false;
  }
  return true;
}

void MmapShmRing::close() {
  releaseConsumer();
  if (base_ != nullptr && base_ != MAP_FAILED) {
    ::munmap(base_, mappedSize_);
  }
  base_ = nullptr;
  mappedSize_ = 0;
  capacityFrames_ = 0;
  header_ = nullptr;
  mappedIdentity_ = {};
  ownsConsumer_ = false;
  ownedConsumerPid_ = 0;
  ownedConsumerToken_ = 0;
  if (fd_ >= 0) {
    ::close(fd_);
    fd_ = -1;
  }
}

bool MmapShmRing::isMappedObjectStale() const {
  if (!isMapped()) {
    return false;
  }
  ShmObjectIdentity current;
  if (!StatNamedShmObject(name_, current)) {
    return true;
  }
  return ShmObjectIdentityChanged(mappedIdentity_, current);
}

void MmapShmRing::clearError() {
  lastErrorCode_ = ShmRingErrorCode::None;
  lastErrno_ = 0;
  lastError_.clear();
}

void MmapShmRing::recordError(ShmRingErrorCode code, std::string message, int err) {
  lastErrorCode_ = code;
  lastErrno_ = err;
  lastError_ = std::move(message);
}

void MmapShmRing::recordErrno(ShmRingErrorCode code, const char* operation, int err) {
  std::ostringstream out;
  out << operation << " failed";
  if (err != 0) {
    out << ": " << std::strerror(err) << " (errno " << err << ")";
  }
  recordError(code, out.str(), err);
}

void MmapShmRing::setDaemonReady() {
  if (!isMapped() || role_ != ShmRingRole::Consumer || !ownsConsumer_) {
    return;
  }
  header_->daemon_ready.store(1, std::memory_order_release);
}

bool MmapShmRing::daemonReady() const {
  return isMapped() && header_->daemon_ready.load(std::memory_order_acquire) != 0;
}

uint64_t MmapShmRing::consumerEpoch() const {
  if (!isMapped()) {
    return 0;
  }
  return header_->consumer_epoch.load(std::memory_order_acquire);
}

ShmProducerDiagnostics MmapShmRing::producerDiagnostics() const {
  ShmProducerDiagnostics diagnostics;
  if (!isMapped()) {
    return diagnostics;
  }
  diagnostics.overrunEvents =
      header_->producer_overrun_events.load(std::memory_order_acquire);
  diagnostics.droppedFrames =
      header_->producer_dropped_frames.load(std::memory_order_acquire);
  diagnostics.notReadyDroppedFrames =
      header_->producer_not_ready_dropped_frames.load(std::memory_order_acquire);
  diagnostics.laneQueueDrops =
      header_->lane_queue_drops.load(std::memory_order_acquire);
  diagnostics.laneTimestampMismatches =
      header_->lane_timestamp_mismatches.load(std::memory_order_acquire);
  diagnostics.laneFrameMismatchDroppedFrames =
      header_->lane_frame_mismatch_dropped_frames.load(std::memory_order_acquire);
  diagnostics.consumerResets =
      header_->consumer_resets.load(std::memory_order_acquire);
  return diagnostics;
}

bool MmapShmRing::claimConsumer() {
  if (!isMapped() || header_ == nullptr || role_ != ShmRingRole::Consumer) {
    return false;
  }

  const uint32_t pid = static_cast<uint32_t>(::getpid());
  for (;;) {
    uint32_t expected = 0;
    if (header_->consumer_pid.compare_exchange_strong(
            expected, pid, std::memory_order_acq_rel, std::memory_order_acquire)) {
      break;
    }
    if (ProcessIsAlive(expected)) {
      return false;
    }
    uint32_t stalePid = expected;
    header_->consumer_pid.compare_exchange_strong(
        stalePid, 0, std::memory_order_acq_rel, std::memory_order_acquire);
  }

  ownedConsumerPid_ = pid;
  ownedConsumerToken_ =
      (static_cast<uint64_t>(pid) << 32) |
      (gNextConsumerToken.fetch_add(1, std::memory_order_relaxed) + 1);
  ownsConsumer_ = true;
  header_->consumer_token.store(ownedConsumerToken_, std::memory_order_release);
  header_->daemon_ready.store(0, std::memory_order_release);

  // A new consumer is a new stream session. Discard everything produced
  // before this claim so reconnect cannot replay the old daemon's backlog.
  const uint64_t write = header_->write_index.load(std::memory_order_acquire);
  header_->read_index.store(write, std::memory_order_release);
  header_->consumer_epoch.fetch_add(1, std::memory_order_acq_rel);
  header_->consumer_resets.fetch_add(1, std::memory_order_relaxed);
  return true;
}

void MmapShmRing::releaseConsumer() {
  if (!ownsConsumer_ || header_ == nullptr || role_ != ShmRingRole::Consumer) {
    return;
  }
  header_->daemon_ready.store(0, std::memory_order_release);
  const uint64_t token = header_->consumer_token.load(std::memory_order_acquire);
  if (token == ownedConsumerToken_) {
    header_->consumer_token.store(0, std::memory_order_release);
    uint32_t expectedPid = ownedConsumerPid_;
    header_->consumer_pid.compare_exchange_strong(
        expectedPid, 0, std::memory_order_acq_rel, std::memory_order_acquire);
  }
  ownsConsumer_ = false;
}

bool MmapShmRing::consumerOwnershipValid() const {
  if (role_ != ShmRingRole::Consumer) {
    return true;
  }
  return ownsConsumer_ && header_ != nullptr &&
         header_->consumer_pid.load(std::memory_order_acquire) == ownedConsumerPid_ &&
         header_->consumer_token.load(std::memory_order_acquire) == ownedConsumerToken_;
}

bool MmapShmRing::indicesAreSane(uint64_t write, uint64_t read) const {
  return capacityFrames_ > 0 && write >= read && (write - read) < capacityFrames_;
}

void MmapShmRing::repairCorruptIndices(uint64_t write) const {
  if (role_ != ShmRingRole::Consumer || !consumerOwnershipValid()) {
    return;
  }
  // The 0666 object is a documented local-integrity boundary. If another
  // process corrupts either monotonic index, discard the entire questionable
  // interval instead of treating an underflow as a full ring and replaying it.
  header_->read_index.store(write, std::memory_order_release);
  header_->consumer_resets.fetch_add(1, std::memory_order_relaxed);
}

float* MmapShmRing::samples() const {
  return reinterpret_cast<float*>(static_cast<char*>(base_) + ShmSamplesOffset());
}

std::size_t MmapShmRing::availableToRead() const {
  if (!isMapped() || capacityFrames_ == 0 || !consumerOwnershipValid()) {
    return 0;
  }
  const uint64_t w = header_->write_index.load(std::memory_order_acquire);
  const uint64_t r = header_->read_index.load(std::memory_order_acquire);
  if (!indicesAreSane(w, r)) {
    repairCorruptIndices(w);
    return 0;
  }
  const std::size_t used = static_cast<std::size_t>(w - r);
  return used;
}

std::size_t MmapShmRing::availableToWrite() const {
  if (!isMapped() || capacityFrames_ == 0) {
    return 0;
  }
  const uint64_t w = header_->write_index.load(std::memory_order_acquire);
  const uint64_t r = header_->read_index.load(std::memory_order_acquire);
  if (!indicesAreSane(w, r)) {
    return 0;
  }
  const std::size_t used = static_cast<std::size_t>(w - r);
  return capacityFrames_ - used - 1;
}

std::size_t MmapShmRing::pushInterleaved(const float* interleaved, std::size_t frameCount) {
  if (header_ == nullptr || capacityFrames_ == 0 || interleaved == nullptr || frameCount == 0) {
    return 0;
  }
  const std::size_t canWrite = std::min(frameCount, availableToWrite());
  if (canWrite == 0) {
    return 0;
  }

  const std::size_t cap = capacityFrames_;
  uint64_t w = header_->write_index.load(std::memory_order_relaxed);
  float* dst = samples();

  // A bounded transfer spans at most the tail and the head of the ring.
  // Compute wraparound once, then copy contiguous stereo frames.
  const std::size_t start = static_cast<std::size_t>(w % cap);
  const std::size_t first = std::min(canWrite, cap - start);
  std::memcpy(dst + start * kShmChannels, interleaved,
              first * kShmChannels * sizeof(float));
  if (first < canWrite) {
    std::memcpy(dst, interleaved + first * kShmChannels,
                (canWrite - first) * kShmChannels * sizeof(float));
  }
  w += canWrite;
  header_->write_index.store(w, std::memory_order_release);
  return canWrite;
}

std::size_t MmapShmRing::popInterleaved(float* interleaved, std::size_t frameCount) {
  if (header_ == nullptr || capacityFrames_ == 0 || interleaved == nullptr || frameCount == 0) {
    return 0;
  }
  const std::size_t canRead = std::min(frameCount, availableToRead());
  if (canRead == 0) {
    return 0;
  }

  const std::size_t cap = capacityFrames_;
  uint64_t r = header_->read_index.load(std::memory_order_relaxed);
  const float* src = samples();

  const std::size_t start = static_cast<std::size_t>(r % cap);
  const std::size_t first = std::min(canRead, cap - start);
  std::memcpy(interleaved, src + start * kShmChannels,
              first * kShmChannels * sizeof(float));
  if (first < canRead) {
    std::memcpy(interleaved + first * kShmChannels, src,
                (canRead - first) * kShmChannels * sizeof(float));
  }
  r += canRead;
  header_->read_index.store(r, std::memory_order_release);
  return canRead;
}

std::size_t MmapShmRing::popToPlanar(float* const channelData[2], std::size_t frameCount) {
  if (!isMapped() || capacityFrames_ == 0 || channelData == nullptr ||
      channelData[0] == nullptr || channelData[1] == nullptr) {
    return 0;
  }
  const std::size_t canRead = std::min(frameCount, availableToRead());
  if (canRead == 0) {
    return 0;
  }

  const std::size_t cap = capacityFrames_;
  uint64_t r = header_->read_index.load(std::memory_order_relaxed);
  const float* src = samples();

  const std::size_t start = static_cast<std::size_t>(r % cap);
  const std::size_t first = std::min(canRead, cap - start);
  const float* tail = src + start * kShmChannels;
  for (std::size_t i = 0; i < first; ++i) {
    channelData[0][i] = tail[i * kShmChannels + 0];
    channelData[1][i] = tail[i * kShmChannels + 1];
  }
  for (std::size_t i = 0; i < canRead - first; ++i) {
    channelData[0][first + i] = src[i * kShmChannels + 0];
    channelData[1][first + i] = src[i * kShmChannels + 1];
  }
  r += canRead;
  header_->read_index.store(r, std::memory_order_release);
  return canRead;
}

}  // namespace apm44
