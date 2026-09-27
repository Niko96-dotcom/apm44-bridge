#pragma once

#include "engine/VirtualDeviceFeed.h"

namespace apm44 {

enum class VirtualFeedStaleAction { None, StopForRemap, StopForExit };

struct StaleRingRecoveryPlan {
  VirtualFeedStaleAction action;
  bool restartOutput;
};

// Decides what BridgeEngine::pollVirtualFeedStaleRing() does after it has
// stopped output IO and polled the stale ring. `epochResetOk` only matters
// for Remapped. Once the daemon has decided to exit, output IO stays stopped:
// restarting it would briefly run the IOProc on a feed it has given up on.
inline StaleRingRecoveryPlan PlanStaleRingRecovery(StaleRingPollResult pollResult,
                                                   bool epochResetOk) {
  switch (pollResult) {
    case StaleRingPollResult::Ok:
      return {VirtualFeedStaleAction::None, true};
    case StaleRingPollResult::Remapped:
      if (epochResetOk) {
        return {VirtualFeedStaleAction::StopForRemap, true};
      }
      return {VirtualFeedStaleAction::StopForExit, false};
    case StaleRingPollResult::MustExit:
      return {VirtualFeedStaleAction::StopForExit, false};
  }
  return {VirtualFeedStaleAction::StopForExit, false};
}

}  // namespace apm44
