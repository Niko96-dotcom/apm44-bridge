#pragma once

#include <string>

namespace apm44 {

// The values the Swift app copies from the helper, as one JSON object:
// exit codes by name, hal_fill_floor_ms, device_uid and metrics_json_keys
// (every key of a metrics JSON line, read from ToJsonLine's output).
// `--print-contract` prints it; tests/test_helper_contract.swift compares it
// with the app's copies, so a value changed on one side only fails the test.
std::string HelperContractJson();

}  // namespace apm44
