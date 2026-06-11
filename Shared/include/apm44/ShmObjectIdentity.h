#pragma once

#include "apm44/ShmRingLayout.h"

#include <cstddef>
#include <fcntl.h>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace apm44 {

struct ShmObjectIdentity {
  dev_t st_dev = 0;
  ino_t st_ino = 0;
  // SHM-03: capture the object size at mapping time so a live
  // generation read can detect a size change and treat the object as
  // stale. `0` means "size unknown" (i.e., the stat failed).
  std::size_t size = 0;
  uint32_t driver_generation = 0;
  bool valid = false;
  bool has_generation = false;
};

inline bool ReadLiveDriverGeneration(const std::string& name, uint32_t& out) {
  const int fd = ::shm_open(name.c_str(), O_RDONLY, 0);
  if (fd < 0) {
    return false;
  }
  // SHM-03: refuse to map or read a header from an object that is
  // smaller than the header itself.
  struct stat st {};
  if (::fstat(fd, &st) != 0 || st.st_size < static_cast<off_t>(sizeof(ShmRingHeader))) {
    ::close(fd);
    return false;
  }
  void* base =
      ::mmap(nullptr, sizeof(ShmRingHeader), PROT_READ, MAP_SHARED, fd, 0);
  if (base == MAP_FAILED) {
    ::close(fd);
    return false;
  }
  const auto* header = static_cast<const ShmRingHeader*>(base);
  out = header->driver_generation.load(std::memory_order_relaxed);
  ::munmap(base, sizeof(ShmRingHeader));
  ::close(fd);
  return true;
}

inline bool StatNamedShmObject(const std::string& name, ShmObjectIdentity& out) {
  out = {};
  const int fd = ::shm_open(name.c_str(), O_RDONLY, 0);
  if (fd < 0) {
    return false;
  }
  struct stat st {};
  const bool ok = ::fstat(fd, &st) == 0;
  ::close(fd);
  if (!ok) {
    return false;
  }
  out.st_dev = st.st_dev;
  out.st_ino = st.st_ino;
  out.size = static_cast<std::size_t>(st.st_size);
  out.valid = true;
  uint32_t generation = 0;
  if (ReadLiveDriverGeneration(name, generation)) {
    out.driver_generation = generation;
    out.has_generation = true;
  }
  return true;
}

inline bool ShmObjectIdentityChanged(const ShmObjectIdentity& mapped,
                                     const ShmObjectIdentity& current) {
  if (!mapped.valid || !current.valid) {
    return false;
  }
  if (mapped.st_ino != 0 || current.st_ino != 0) {
    if (mapped.st_dev != current.st_dev || mapped.st_ino != current.st_ino) {
      return true;
    }
  }
  if (mapped.size != 0 && current.size != 0 && mapped.size != current.size) {
    // SHM-03: a size change in the live object means the producer
    // truncated, grew, or replaced the shm. Treat as stale.
    return true;
  }
  if (mapped.has_generation && current.has_generation &&
      mapped.driver_generation != current.driver_generation) {
    return true;
  }
  return false;
}

}  // namespace apm44
