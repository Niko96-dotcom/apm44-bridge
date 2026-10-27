#include "HelperContract.h"

#include "DaemonExitCodes.h"
#include "engine/BridgeEngine.h"
#include "engine/BridgeMetrics.h"

#include <apm44/HalDeviceIdentity.h>

#include <cstddef>
#include <sstream>
#include <string>

namespace apm44 {

namespace {

// Writes the keys of one metrics JSON line as a JSON array. The keys come
// from ToJsonLine's own output, so no second key list exists to drift. The
// line is one flat object whose only string value ("medium" here) holds no
// '"', so every key is the quoted text that follows '{' or ','.
void WriteMetricsJsonKeys(std::ostringstream& json) {
  const std::string line = ToJsonLine(MakeBridgeMetrics(MetricsSnapshot{}, 0.0, "medium"));
  json << '[';
  bool first = true;
  for (std::size_t pos = line.find_first_of("{,"); pos != std::string::npos;
       pos = line.find_first_of("{,", pos + 1)) {
    if (pos + 1 >= line.size() || line[pos + 1] != '"') {
      continue;
    }
    const std::size_t end = line.find('"', pos + 2);
    if (end == std::string::npos) {
      break;
    }
    json << (first ? "" : ",") << line.substr(pos + 1, end - pos);
    first = false;
  }
  json << ']';
}

}  // namespace

// The UID is a fixed ASCII constant with no characters that need JSON escaping.
std::string HelperContractJson() {
  std::ostringstream json;
  json << "{\"exit_codes\":{"
       << "\"stale_shm_ring\":" << kExitStaleShmRing << ','
       << "\"singleton_busy\":" << kExitSingletonBusy << ','
       << "\"loaded_driver_build_mismatch\":" << kExitLoadedDriverBuildMismatch << "},"
       << "\"hal_fill_floor_ms\":" << kHalTargetFillFloorMs << ','
       << "\"device_uid\":\"" << kApm44DeviceUid << "\","
       << "\"metrics_json_keys\":";
  WriteMetricsJsonKeys(json);
  json << '}';
  return json.str();
}

}  // namespace apm44
