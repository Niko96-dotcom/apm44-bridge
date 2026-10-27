#include <catch2/catch_test_macros.hpp>

#include "HelperContract.h"

// Pins the JSON that `--print-contract` prints. tests/test_helper_contract.swift
// runs the built helper and compares the same object with the app's copies.
TEST_CASE("HelperContractJson reports exit codes, HAL fill floor and device UID",
          "[helper_contract]") {
  CHECK(apm44::HelperContractJson() ==
        "{\"exit_codes\":{\"stale_shm_ring\":42,\"singleton_busy\":43,"
        "\"loaded_driver_build_mismatch\":44},\"hal_fill_floor_ms\":20,"
        "\"device_uid\":\"com.niko.apm44.bridge.device\"}");
}
