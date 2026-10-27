#include <catch2/catch_test_macros.hpp>

#include "HelperContract.h"

// Pins the JSON that `--print-contract` prints. tests/test_helper_contract.swift
// runs the built helper and compares the same object with the app's copies.
TEST_CASE("HelperContractJson reports exit codes, HAL fill floor, device UID and metrics keys",
          "[helper_contract]") {
  CHECK(apm44::HelperContractJson() ==
        "{\"exit_codes\":{\"stale_shm_ring\":42,\"singleton_busy\":43,"
        "\"loaded_driver_build_mismatch\":44},\"hal_fill_floor_ms\":20,"
        "\"device_uid\":\"com.niko.apm44.bridge.device\","
        "\"metrics_json_keys\":[\"fill_ms\",\"ratio\",\"ppm\",\"underruns\",\"overruns\","
        "\"xruns\",\"input_dropped_frames\",\"producer_overrun_events\","
        "\"producer_dropped_frames\",\"producer_not_ready_dropped_frames\","
        "\"lane_queue_drops\",\"lane_timestamp_mismatches\","
        "\"lane_frame_mismatch_dropped_frames\",\"consumer_resets\","
        "\"output_starvation_frames\",\"partial_shortage_events\","
        "\"converter_reset_events\",\"rebuffer_events\",\"recovery_fade_events\","
        "\"estimated_rt_ms\",\"target_fill_ms\",\"src_quality\"]}");
}
