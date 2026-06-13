# Architecture Research

**Domain:** APM44 Bridge public-release safety fixes
**Researched:** 2026-06-13
**Confidence:** HIGH

## System View

```text
---------------------------------------------------------------+
|                         Public CI                             |
| .github/workflows/ci.yml -> CMake/ctest -> release scripts    |
|                              -> Swift build/tests             |
+---------------------------------------------------------------+
|                      Installer Surface                         |
| build-release-dmg.sh -> Install APM44 Bridge.command          |
| sudo HAL driver install -> sudo app bundle replace -> open app |
+---------------------------------------------------------------+
|                        Swift App                               |
| DeviceCatalog.refresh()   BridgeProcessManager metrics state  |
+---------------------------------------------------------------+
|                        Daemon                                  |
| MetricsPublisher      AudioConverterSrc legacy comparison      |
+---------------------------------------------------------------+
|                        HAL Driver                              |
| ShmIoHandler start/stop, mixed output, mono lane pairing       |
+---------------------------------------------------------------+
```

## Component Responsibilities

| Component | Current Role | v0.6 Change |
|-----------|--------------|-------------|
| `ShmIoHandler::OnProcessMixedOutput` | Applies stream processing and pushes stereo/mono audio to shm | Return immediately when `ioRunning_` is false. |
| `PendingLaneBlock` | Holds queued mono channel block and `sampleTime` | Also hold `zeroTimestamp` so rollover logic can compare logical absolute times. |
| `flushPendingLanes()` | Pairs or drops queued mono lanes | Use an explicit same-block predicate; drop older logical block on unmatched mismatches. |
| `AudioConverterSrc` | Debug AudioToolbox converter path | Either own callback input buffers or remove the exposed debug path. |
| `MetricsPublisherState` | Atomic-field metrics seqlock | Store doubles as lock-free atomic `uint64_t` bit patterns or statically require lock-free double atomics. |
| `DeviceCatalog.refresh()` | Runs helper `--list-devices` | Discard or drain stderr before `waitUntilExit()`. |
| `BridgeProcessManager` | Tracks metrics and stale UI state | Reset `lastMetricsAt` wherever metrics state is reset. |
| `build-release-dmg.sh` | Generates app/driver DMG command installer | Replace existing app bundle with `sudo rm -rf`, `sudo ditto`, `sudo chown`. |
| `.github/workflows/ci.yml` | Public macOS CI | Run `tests/test_release_scripts.sh` after native tests. |

## HAL Lane Pairing Data Flow

Current:

```text
OnProcessMixedOutput(zeroTimestamp ignored, timestamp)
  -> pushMonoLane(stream, frames, frameCount, timestamp)
  -> enqueueLane(channel, sampleTime)
  -> flushPendingLanes()
       if sampleTime mismatch:
         search ahead for exact queued sampleTime
       pushLanePair(left, right) even if no match found
```

Recommended:

```text
OnProcessMixedOutput(zeroTimestamp, timestamp)
  -> pushMonoLane(stream, zeroTimestamp, timestamp, frames, frameCount)
  -> enqueueLane(channel, zeroTimestamp, timestamp)
  -> flushPendingLanes()
       if SameLogicalLaneBlock(left, right):
         push pair and drop both
       else if queued exact timestamp match exists:
         drop stale lanes and retry
       else:
         drop the lane with older logical time and retry
```

`SameLogicalLaneBlock` should keep the existing exact timestamp tolerance and
make rollover tolerance narrow and named. The user-provided rollover example
differs by 68 frames in logical time, so a 128-frame tolerance is a defensible
starting point.

## Release Installer Data Flow

Current generated command:

```text
sudo install HAL driver
verify driver hash
restart coreaudiod
cp -R app to /Applications
open app
```

Recommended generated command:

```text
sudo install HAL driver
verify driver hash
restart coreaudiod
sudo rm -rf "/Applications/APM44 Bridge.app"
sudo ditto "$DIR/APM44 Bridge.app" "/Applications/APM44 Bridge.app"
sudo chown -R root:wheel "/Applications/APM44 Bridge.app"
open "/Applications/APM44 Bridge.app"
```

The installer already requires admin rights for the HAL driver, so the app
bundle replacement should be equally deterministic.

## Metrics Data Flow

Current:

```text
BridgeEngine::onOutput PublishGuard
  -> PublishMetrics()
       sequence odd
       atomic<double> payload fields
       atomic<uint64_t> counters
       sequence even
```

Recommended:

```text
BridgeEngine::onOutput PublishGuard
  -> PublishMetrics()
       sequence odd
       atomic<uint64_t> packed double payload fields
       atomic<uint64_t> counters
       sequence even

ReadMetrics()
  -> stable even sequence
  -> unpack double payload fields
```

This preserves the current seqlock read shape while removing dependence on
`std::atomic<double>` lock-freedom.

## Suggested Phase Shape

Because v0.5 ended at Phase 22, v0.6 should continue with:

| Phase | Name | Goal |
|-------|------|------|
| 23 | HAL Runtime Pairing Safety | Fix timestamp pairing, IO stopped guard, and stale drop-policy comment. |
| 24 | Realtime Converter and Metrics Safety | Fix/remove legacy converter and replace possibly-locking metrics double atomics. |
| 25 | App and Release Automation Reliability | Harden DMG installer copy, DeviceCatalog stderr, metrics timestamp reset, and GitHub CI release-script tests. |
| 26 | Regression and Release Safety Closure | Run full local gates and reconcile all v0.6 requirements. |

## Integration Risks

| Risk | Mitigation |
|------|------------|
| Rollover predicate becomes too broad | Use explicit tolerance and tests for unrelated mismatch rejection. |
| Dropping older logical lane causes queue churn | Continue loop after each drop; bounded queue already exists. |
| Removing legacy converter creates broad build churn | If removal is chosen, remove CLI option, engine field, CMake source, docs, and tests in one phase. |
| Bit-packed metrics change breaks JSON expectations | Keep `ReadMetrics()` returning the same `MetricsSnapshot` shape; existing JSON tests should still pass. |
| Swift private state is hard to test | Use existing `@testable` target plus a narrow internal testing hook or source guard. |

---
*Architecture research for: APM44 Bridge v0.6 Public Release Safety Fixes*
*Researched: 2026-06-13*
