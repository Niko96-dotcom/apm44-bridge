#pragma once

#include <apm44/MmapShmRing.h>

#include <aspl/ControlRequestHandler.hpp>
#include <aspl/IORequestHandler.hpp>

#include <memory>
#include <vector>

namespace apm44 {

class ShmIoHandler : public aspl::ControlRequestHandler, public aspl::IORequestHandler {
 public:
  OSStatus OnStartIO() override;
  void OnStopIO() override;

  void OnWriteMixedOutput(const std::shared_ptr<aspl::Stream>& stream,
                          Float64 zeroTimestamp,
                          Float64 timestamp,
                          const void* buff,
                          UInt32 buffBytesSize) override;

 private:
  MmapShmRing ring_;
  std::vector<float> convertScratch_;
};

}  // namespace apm44
