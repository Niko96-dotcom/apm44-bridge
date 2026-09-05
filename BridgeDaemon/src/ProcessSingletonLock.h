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

  static std::string DefaultPath();

 private:
  int fileDescriptor_ = -1;
  std::string lastError_;
};

}  // namespace apm44
