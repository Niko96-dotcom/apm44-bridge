#include "apm44/MmapShmRing.h"

#include <algorithm>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace apm44 {

namespace {

constexpr int kMapProt = PROT_READ | PROT_WRITE;

}  // namespace

MmapShmRing::~MmapShmRing() { close(); }

bool MmapShmRing::create(uint32_t capacityFrames) {
  close();
  role_ = ShmRingRole::Producer;

  const std::size_t totalSize = ShmTotalSize(capacityFrames);
  // Driver runs in coreaudiod; daemon runs as the logged-in user — world rw required.
  ::shm_unlink(kShmRingName);
  fd_ = ::shm_open(kShmRingName, O_CREAT | O_RDWR | O_EXCL, 0666);
  if (fd_ < 0 && errno == EEXIST) {
    fd_ = ::shm_open(kShmRingName, O_RDWR, 0666);
    if (fd_ >= 0) {
      ::fchmod(fd_, 0666);
    }
  }
  if (fd_ < 0) {
    return false;
  }
  if (::fchmod(fd_, 0666) != 0) {
    // Continue; mode at create time should already allow daemon access.
  }
  if (::ftruncate(fd_, static_cast<off_t>(totalSize)) != 0) {
    close();
    return false;
  }

  base_ = ::mmap(nullptr, totalSize, kMapProt, MAP_SHARED, fd_, 0);
  if (base_ == MAP_FAILED) {
    base_ = nullptr;
    close();
    return false;
  }
  mappedSize_ = totalSize;
  header_ = static_cast<ShmRingHeader*>(base_);
  std::memset(base_, 0, totalSize);

  header_->magic = kShmMagic;
  header_->version = kShmVersion;
  header_->capacity_frames = capacityFrames;
  header_->sample_rate = 44100;
  header_->channels = kShmChannels;
  header_->write_index.store(0, std::memory_order_relaxed);
  header_->read_index.store(0, std::memory_order_relaxed);
  header_->daemon_ready.store(0, std::memory_order_relaxed);
  header_->driver_generation.fetch_add(1, std::memory_order_relaxed);
  return true;
}

bool MmapShmRing::open(ShmRingRole role) {
  close();
  role_ = role;

  fd_ = ::shm_open(kShmRingName, O_RDWR, 0);
  if (fd_ < 0) {
    return false;
  }

  struct stat st {};
  if (::fstat(fd_, &st) != 0 || st.st_size <= 0) {
    close();
    return false;
  }
  mappedSize_ = static_cast<std::size_t>(st.st_size);
  base_ = ::mmap(nullptr, mappedSize_, kMapProt, MAP_SHARED, fd_, 0);
  if (base_ == MAP_FAILED) {
    base_ = nullptr;
    close();
    return false;
  }
  header_ = static_cast<ShmRingHeader*>(base_);
  if (!ValidateShmHeader(*header_)) {
    close();
    return false;
  }
  return true;
}

void MmapShmRing::close() {
  if (base_ != nullptr && base_ != MAP_FAILED) {
    ::munmap(base_, mappedSize_);
  }
  base_ = nullptr;
  mappedSize_ = 0;
  header_ = nullptr;
  if (fd_ >= 0) {
    ::close(fd_);
    fd_ = -1;
  }
}

void MmapShmRing::setDaemonReady() {
  if (header_ != nullptr) {
    header_->daemon_ready.store(1, std::memory_order_release);
  }
}

float* MmapShmRing::samples() const {
  return reinterpret_cast<float*>(static_cast<char*>(base_) + ShmSamplesOffset());
}

std::size_t MmapShmRing::availableToRead() const {
  const uint64_t w = header_->write_index.load(std::memory_order_acquire);
  const uint64_t r = header_->read_index.load(std::memory_order_acquire);
  return static_cast<std::size_t>(w - r);
}

std::size_t MmapShmRing::availableToWrite() const {
  const std::size_t cap = header_->capacity_frames;
  const std::size_t used = availableToRead();
  return cap > used ? cap - used - 1 : 0;
}

std::size_t MmapShmRing::pushInterleaved(const float* interleaved, std::size_t frameCount) {
  if (header_ == nullptr || interleaved == nullptr || frameCount == 0) {
    return 0;
  }
  const std::size_t canWrite = std::min(frameCount, availableToWrite());
  if (canWrite == 0) {
    return 0;
  }

  const uint32_t cap = header_->capacity_frames;
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
  if (header_ == nullptr || interleaved == nullptr || frameCount == 0) {
    return 0;
  }
  const std::size_t canRead = std::min(frameCount, availableToRead());
  if (canRead == 0) {
    return 0;
  }

  const uint32_t cap = header_->capacity_frames;
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
  if (channelData == nullptr || channelData[0] == nullptr || channelData[1] == nullptr) {
    return 0;
  }
  const std::size_t canRead = std::min(frameCount, availableToRead());
  if (canRead == 0 || header_ == nullptr) {
    return 0;
  }

  const uint32_t cap = header_->capacity_frames;
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
