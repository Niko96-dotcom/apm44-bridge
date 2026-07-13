#include "ProcessSingletonLock.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace apm44 {

ProcessSingletonLock::~ProcessSingletonLock() { release(); }

std::string ProcessSingletonLock::DefaultPath() {
  return "/tmp/apm44-bridge." + std::to_string(static_cast<unsigned long>(::getuid())) +
         ".lock";
}

bool ProcessSingletonLock::acquire(const std::string& path) {
  release();
  lastError_.clear();

  const int fd = ::open(path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0) {
    lastError_ = "open singleton lock failed: " + std::string(std::strerror(errno));
    return false;
  }

  struct stat status {};
  if (::fstat(fd, &status) != 0 || !S_ISREG(status.st_mode) || status.st_uid != ::getuid()) {
    lastError_ = "singleton lock is not a regular file owned by the current user";
    ::close(fd);
    return false;
  }

  if (::flock(fd, LOCK_EX | LOCK_NB) != 0) {
    lastError_ = errno == EWOULDBLOCK
                     ? "another apm44-bridge helper already owns the singleton lock"
                     : "flock singleton lock failed: " + std::string(std::strerror(errno));
    ::close(fd);
    return false;
  }

  const std::string pid = std::to_string(static_cast<long long>(::getpid())) + "\n";
  if (::ftruncate(fd, 0) == 0) {
    (void)::pwrite(fd, pid.data(), pid.size(), 0);
  }
  fileDescriptor_ = fd;
  return true;
}

void ProcessSingletonLock::release() {
  if (fileDescriptor_ < 0) {
    return;
  }
  (void)::flock(fileDescriptor_, LOCK_UN);
  ::close(fileDescriptor_);
  fileDescriptor_ = -1;
}

}  // namespace apm44
