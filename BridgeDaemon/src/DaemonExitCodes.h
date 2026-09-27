#pragma once

#include <apm44/MmapShmRing.h>

namespace apm44 {

// These are the exit codes the menu-bar app classifies; mirrored by
// `DaemonExitCode` in App/APM44Bridge/BridgeProcessPolicy.swift; change both
// together.
inline constexpr int kExitFailure = 1;
// Stale shared-memory ring, the app retries.
inline constexpr int kExitStaleShmRing = 42;
// Another apm44-bridge helper owns the singleton lock; the app does not retry.
inline constexpr int kExitSingletonBusy = 43;
// coreaudiod runs a different driver build; the app does not retry.
inline constexpr int kExitLoadedDriverBuildMismatch = 44;

// Only a lock held by another process means another helper is running. An
// unusable lock file is an ordinary failure, so the app retries and then
// shows the helper's diagnostic.
constexpr int ExitCodeForSingletonFailure(bool heldByAnotherProcess) {
  return heldByAnotherProcess ? kExitSingletonBusy : kExitFailure;
}

constexpr int ExitCodeForPrepareFailure(bool virtualDevice, ShmRingErrorCode code) {
  if (virtualDevice && code == ShmRingErrorCode::ProducerBuildMismatch) {
    return kExitLoadedDriverBuildMismatch;
  }
  return kExitFailure;
}

}  // namespace apm44
