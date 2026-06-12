#include "hal/DeviceEnumerator.h"

#include <apm44/MmapShmRing.h>

#include <CoreAudio/CoreAudio.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
#include <string_view>
#include <thread>

namespace {

constexpr std::string_view kApm44DeviceUid = "com.niko.apm44.bridge.device";

OSStatus ProbeIoProc(AudioDeviceID,
                     const AudioTimeStamp*,
                     const AudioBufferList*,
                     const AudioTimeStamp*,
                     AudioBufferList* outOutputData,
                     const AudioTimeStamp*,
                     void*) {
  if (outOutputData == nullptr) {
    return noErr;
  }
  for (UInt32 i = 0; i < outOutputData->mNumberBuffers; ++i) {
    AudioBuffer& buffer = outOutputData->mBuffers[i];
    if (buffer.mData != nullptr && buffer.mDataByteSize > 0) {
      std::memset(buffer.mData, 0, buffer.mDataByteSize);
    }
  }
  return noErr;
}

double ParseTimeoutSeconds(int argc, char* argv[]) {
  for (int i = 1; i + 1 < argc; ++i) {
    if (std::string_view(argv[i]) == "--timeout-sec") {
      try {
        return std::clamp(std::stod(argv[i + 1]), 0.5, 30.0);
      } catch (...) {
        return 5.0;
      }
    }
  }
  return 5.0;
}

bool IsFatalShmOpenFailure(apm44::ShmRingErrorCode code, int err) {
  if (code == apm44::ShmRingErrorCode::InvalidHeader ||
      code == apm44::ShmRingErrorCode::PermissionFailed) {
    return true;
  }
  if ((code == apm44::ShmRingErrorCode::OpenFailed ||
       code == apm44::ShmRingErrorCode::MapFailed) &&
      (err == EACCES || err == EPERM)) {
    return true;
  }
  return false;
}

const char* StatusName(OSStatus status) {
  return status == noErr ? "noErr" : "error";
}

}  // namespace

int main(int argc, char* argv[]) {
  const double timeoutSec = ParseTimeoutSeconds(argc, argv);

  apm44::DeviceEnumerator enumerator;
  const auto device = enumerator.findOutputByUid(kApm44DeviceUid);
  if (!device) {
    std::cerr << "error: APM44 Bridge output device is not visible to Core Audio\n";
    return 1;
  }

  AudioDeviceIOProcID proc = nullptr;
  OSStatus status = AudioDeviceCreateIOProcID(device->deviceId, ProbeIoProc, nullptr, &proc);
  if (status != noErr) {
    std::cerr << "error: AudioDeviceCreateIOProcID failed: " << StatusName(status) << " ("
              << status << ")\n";
    return 2;
  }

  bool started = false;
  auto cleanup = [&]() {
    if (started) {
      AudioDeviceStop(device->deviceId, proc);
    }
    if (proc != nullptr) {
      AudioDeviceDestroyIOProcID(device->deviceId, proc);
      proc = nullptr;
    }
  };

  status = AudioDeviceStart(device->deviceId, proc);
  if (status != noErr) {
    std::cerr << "error: AudioDeviceStart failed: " << StatusName(status) << " (" << status
              << ")\n";
    cleanup();
    return 3;
  }
  started = true;

  apm44::MmapShmRing ring;
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::duration<double>(timeoutSec);
  while (!ring.open(apm44::ShmRingRole::Consumer)) {
    if (IsFatalShmOpenFailure(ring.lastErrorCode(), ring.lastErrno())) {
      std::cerr << "error: shm open failed: " << ring.lastError() << "\n";
      cleanup();
      return 4;
    }
    if (std::chrono::steady_clock::now() >= deadline) {
      std::cerr << "error: shm ring did not appear within " << timeoutSec << "s";
      if (!ring.lastError().empty()) {
        std::cerr << ": " << ring.lastError();
      }
      std::cerr << "\n";
      cleanup();
      return 5;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  const auto* header = ring.header();
  ring.setDaemonReady();
  std::cout << "hal_smoke=ok\n";
  std::cout << "device_uid=" << device->uid << "\n";
  std::cout << "device_rate=" << device->nominalRate << "\n";
  std::cout << "shm_name=" << apm44::kShmRingName << "\n";
  std::cout << "helper_build_id=" << apm44::kBuildId << "\n";
  std::cout << "driver_build_id=" << apm44::RenderShmBuildId(header->producer_build_id) << "\n";
  std::cout << "capacity_frames=" << header->capacity_frames << "\n";

  ring.close();
  cleanup();
  return 0;
}
