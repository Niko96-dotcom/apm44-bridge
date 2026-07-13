#include "ParentDeathWatch.h"

#include <cerrno>
#include <thread>
#include <unistd.h>

namespace apm44 {

bool WaitForParentChannelClose(int fileDescriptor) noexcept {
  if (fileDescriptor < 0) {
    return true;
  }
  char byte = 0;
  for (;;) {
    const ssize_t result = ::read(fileDescriptor, &byte, sizeof(byte));
    if (result > 0) {
      continue;
    }
    if (result == 0) {
      return true;
    }
    if (errno != EINTR) {
      return true;
    }
  }
}

void StartParentDeathWatch(int fileDescriptor, ParentDeathCallback callback) {
  std::thread([fileDescriptor, callback] {
    if (WaitForParentChannelClose(fileDescriptor) && callback != nullptr) {
      callback();
    }
  }).detach();
}

}  // namespace apm44
