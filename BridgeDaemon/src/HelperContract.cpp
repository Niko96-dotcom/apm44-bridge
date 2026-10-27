#include "HelperContract.h"

#include "DaemonExitCodes.h"
#include "engine/BridgeEngine.h"

#include <apm44/HalDeviceIdentity.h>

#include <sstream>

namespace apm44 {

// The UID is a fixed ASCII constant with no characters that need JSON escaping.
std::string HelperContractJson() {
  std::ostringstream json;
  json << "{\"exit_codes\":{"
       << "\"stale_shm_ring\":" << kExitStaleShmRing << ','
       << "\"singleton_busy\":" << kExitSingletonBusy << ','
       << "\"loaded_driver_build_mismatch\":" << kExitLoadedDriverBuildMismatch << "},"
       << "\"hal_fill_floor_ms\":" << kHalTargetFillFloorMs << ','
       << "\"device_uid\":\"" << kApm44DeviceUid << "\"}";
  return json.str();
}

}  // namespace apm44
