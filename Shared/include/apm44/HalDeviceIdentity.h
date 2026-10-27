#pragma once

// Included by the HAL driver (C++17) and the helper (C++20).

namespace apm44 {

// The UID the HAL driver publishes for its virtual output device. The helper
// reports it with --print-contract; HalDriverDetector.deviceUid in the Swift
// app must match it (tests/test_helper_contract.swift).
inline constexpr char kApm44DeviceUid[] = "com.niko.apm44.bridge.device";

}  // namespace apm44
