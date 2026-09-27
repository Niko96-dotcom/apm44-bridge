#pragma once

#include <string>

namespace apm44 {

class ProcessSingletonLock {
 public:
  ProcessSingletonLock() = default;
  ~ProcessSingletonLock();

  ProcessSingletonLock(const ProcessSingletonLock&) = delete;
  ProcessSingletonLock& operator=(const ProcessSingletonLock&) = delete;

  bool acquire(const std::string& path = DefaultPath());
  void release();
  const std::string& lastError() const { return lastError_; }
  // True when the last acquire() failed only because another process holds
  // the lock, as opposed to the lock file being unusable.
  bool heldByAnotherProcess() const { return heldByAnotherProcess_; }

  static std::string DefaultPath();

 private:
  int fileDescriptor_ = -1;
  std::string lastError_;
  bool heldByAnotherProcess_ = false;
};

}  // namespace apm44
