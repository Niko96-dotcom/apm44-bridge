#include "apm44/MmapShmRing.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <sstream>
#include <sys/mman.h>
#include <sys/stat.h>
#include <utility>
#include <unistd.h>

namespace apm44 {

namespace {

constexpr int kMapProt = PROT_READ | PROT_WRITE;

std::atomic<uint32_t> gNextShmDriverGeneration{0};

bool IsPermissionErrno(int err) { return err == EACCES || err == EPERM; }

void CaptureMappedIdentity(int fd, ShmObjectIdentity& identity, uint32_t& generation,
                           const ShmRingHeader* header) {
  identity = {};
  generation = 0;
  if (header != nullptr) {
    generation = header->driver_generation.load(std::memory_order_relaxed);
    identity.driver_generation = generation;
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
  CaptureMappedIdentity(fd_, mappedIdentity_, mappedDriverGeneration_, header_);
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
  CaptureMappedIdentity(fd_, mappedIdentity_, mappedDriverGeneration_, header_);
  return true;
}

void MmapShmRing::close() {
  if (base_ != nullptr && base_ != MAP_FAILED) {
    ::munmap(base_, mappedSize_);
  }
  base_ = nullptr;
  mappedSize_ = 0;
  capacityFrames_ = 0;
  header_ = nullptr;
  mappedIdentity_ = {};
  mappedDriverGeneration_ = 0;
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
  if (!isMapped()) {
    return;
  }
  header_->daemon_ready.store(1, std::memory_order_release);
}

float* MmapShmRing::samples() const {
  return reinterpret_cast<float*>(static_cast<char*>(base_) + ShmSamplesOffset());
}

std::size_t MmapShmRing::availableToRead() const {
  if (!isMapped()) {
    return 0;
  }
  const uint64_t w = header_->write_index.load(std::memory_order_acquire);
  const uint64_t r = header_->read_index.load(std::memory_order_acquire);
  return static_cast<std::size_t>(w - r);
}

std::size_t MmapShmRing::availableToWrite() const {
  if (!isMapped() || capacityFrames_ == 0) {
    return 0;
  }
  const std::size_t used = availableToRead();
  return capacityFrames_ > used ? capacityFrames_ - used - 1 : 0;
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

  for (std::size_t i = 0; i < canWrite; ++i) {
    const std::size_t idx = static_cast<std::size_t>((w + i) % cap);
    dst[idx * kShmChannels + 0] = interleaved[i * kShmChannels + 0];
    dst[idx * kShmChannels + 1] = interleaved[i * kShmChannels + 1];
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

  for (std::size_t i = 0; i < canRead; ++i) {
    const std::size_t idx = static_cast<std::size_t>((r + i) % cap);
    interleaved[i * kShmChannels + 0] = src[idx * kShmChannels + 0];
    interleaved[i * kShmChannels + 1] = src[idx * kShmChannels + 1];
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

  for (std::size_t i = 0; i < canRead; ++i) {
    const std::size_t idx = static_cast<std::size_t>((r + i) % cap);
    channelData[0][i] = src[idx * kShmChannels + 0];
    channelData[1][i] = src[idx * kShmChannels + 1];
  }
  r += canRead;
  header_->read_index.store(r, std::memory_order_release);
  return canRead;
}

}  // namespace apm44
