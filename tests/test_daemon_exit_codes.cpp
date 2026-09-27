#include <catch2/catch_test_macros.hpp>

#include "DaemonExitCodes.h"

static_assert(apm44::kExitStaleShmRing == 42 && apm44::kExitSingletonBusy == 43 &&
              apm44::kExitLoadedDriverBuildMismatch == 44 && apm44::kExitFailure == 1);

TEST_CASE("ExitCodeForSingletonFailure exits 43 only for a lock held elsewhere",
          "[daemon_exit_codes]") {
  CHECK(apm44::ExitCodeForSingletonFailure(true) == 43);
  CHECK(apm44::ExitCodeForSingletonFailure(false) == 1);
}

TEST_CASE("ExitCodeForPrepareFailure maps build mismatch only in virtual mode",
          "[daemon_exit_codes]") {
  using apm44::ShmRingErrorCode;
  struct Row {
    bool virtualDevice;
    ShmRingErrorCode code;
    int expected;
  };
  const Row rows[] = {
      {true, ShmRingErrorCode::ProducerBuildMismatch, 44},
      {false, ShmRingErrorCode::ProducerBuildMismatch, 1},
      {true, ShmRingErrorCode::ConsumerBusy, 1},
      {true, ShmRingErrorCode::None, 1},
      {true, ShmRingErrorCode::OpenFailed, 1},
      {true, ShmRingErrorCode::InvalidHeader, 1},
  };
  for (const auto& row : rows) {
    CHECK(apm44::ExitCodeForPrepareFailure(row.virtualDevice, row.code) == row.expected);
  }
}

TEST_CASE("ExitCodeForPrepareFailure returns failure for all other codes",
          "[daemon_exit_codes]") {
  using apm44::ShmRingErrorCode;
  const ShmRingErrorCode others[] = {
      ShmRingErrorCode::None,
      ShmRingErrorCode::OpenFailed,
      ShmRingErrorCode::CreateFailed,
      ShmRingErrorCode::PermissionFailed,
      ShmRingErrorCode::TruncateFailed,
      ShmRingErrorCode::StatFailed,
      ShmRingErrorCode::EmptyObject,
      ShmRingErrorCode::MapFailed,
      ShmRingErrorCode::InvalidHeader,
      ShmRingErrorCode::HeaderTruncated,
      ShmRingErrorCode::CapacityExceedsObject,
      ShmRingErrorCode::ConsumerBusy,
  };
  for (const auto code : others) {
    CHECK(apm44::ExitCodeForPrepareFailure(true, code) == 1);
    CHECK(apm44::ExitCodeForPrepareFailure(false, code) == 1);
  }
}
