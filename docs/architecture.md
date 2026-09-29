# APM44 Bridge architecture

APM44 Bridge carries stereo audio from a DAW at 44.1 kHz to a real output device at 48 kHz. Code wins over older docs.

## 1. Overview

| Component | Lives in | Job |
|---|---|---|
| Virtual HAL device | `Driver/` on libASPL (`Driver/src/Driver.cpp` / `CreateAPM44Driver`) | Presents "APM44 Bridge" to Core Audio, pushes DAW audio into shared memory |
| Shared-memory ring | `Shared/include/apm44/MmapShmRing.h`, `ShmRingLayout.h`, `ShmObjectIdentity.h` | Lock-free SPSC transport between driver and daemon |
| Helper daemon `apm44-bridge` | `BridgeDaemon/` | Resamples 44.1 kHz to 48 kHz with libsamplerate (`BridgeDaemon/src/engine/LibSamplerateSrc.h` / `LibSamplerateSrc`), servos drift (`Shared/include/apm44/DriftController.h` / `DriftController`), renders to the real device |
| Menu-bar app | `App/APM44Bridge/` | Launches and supervises the daemon as a child process |

Data path:

```
DAW --> [APM44 virtual HAL device] --> ((shm ring)) --> [apm44-bridge] --> real output
        Driver/ (libASPL)              Shared/         BridgeDaemon/        Core Audio
                                                      SRC + drift + IOProc  48 kHz device
```

The app spawns the daemon with `BridgeProcessManager.swift` / `start`
and `BridgeProcessPolicy.swift` / `BridgeLaunchArguments`.
Arguments are `--virtual-device` (HAL mode only, first),
`--output-device UID`, `--target-fill-ms N` (integer),
`--src-quality medium|high|best`, `--metrics-json`,
`--parent-watch-stdin` (see `BridgeDaemon/src/CliOptions.cpp` / `ParseCliOptions`).
Fill comes from `BridgeSettings.swift` / `effectiveTargetFillMs` (the
`LatencyPreset.swift` / `LatencyPreset` value). Quality comes from
`BridgeSettings.effectiveSrcQuality`: the user's override, else the
preset's `defaultSrcQuality`.

Metrics flow daemon-stdout to app UI. Each control-loop tick prints one
JSON line (`BridgeDaemon/src/engine/BridgeMetrics.h` / `ToJsonLine`).
The app buffers pipe bytes (`BridgeProcessPolicy.swift` / `DaemonStdoutLineBuffer`),
decodes them (`App/APM44Bridge/MetricsParser.swift` / `MetricsParser`)
into `BridgeMetricsSnapshot.swift` / `BridgeMetricsSnapshot`, keeps the
last 20 stderr lines (`DaemonStderrTail`), and sanitizes diagnostics to
one 240-char line (`BridgeDiagnostics`).

Parent death uses stdin EOF, not polling. The app gives the child a
pipe as stdin and closes its own read end
(`BridgeProcessManager.swift` / `start`). The daemon watches with
`BridgeDaemon/src/ParentDeathWatch.h` / `StartParentDeathWatch` and
`WaitForParentChannelClose`: EOF (or any read error) calls
`BridgeEngine::requestStop`.

Single instance uses a file lock. `BridgeDaemon/src/ProcessSingletonLock.h` /
`ProcessSingletonLock` locks `/tmp/apm44-bridge.<uid>.lock`
(`ProcessSingletonLock.cpp` / `DefaultPath`) with non-blocking `flock`.

Driver and daemon share the ring header, not code paths.
Shared fields (`Shared/include/apm44/ShmRingLayout.h` / `ShmRingHeader`):
magic, version, capacity, rate, channels, `producer_build_id`,
`write_index`/`read_index`, `daemon_ready`, `driver_generation`,
`producer_epoch`/`consumer_epoch`, `consumer_pid`/`consumer_token`,
and producer diagnostic counters.
Identity (`Shared/include/apm44/ShmObjectIdentity.h` / `ShmObjectIdentity`)
is `st_dev`/`st_ino`, object size, and `driver_generation`.
The driver creates the object (`Driver/src/ShmIoHandler.cpp` / `ensureRingReady`
calls `MmapShmRing::create`, which unlinks then re-creates the shm name).
The daemon's audio feed opens it as consumer (`BridgeDaemon/src/engine/VirtualDeviceFeed.cpp` / `open`);
`--shm-status` opens it as an observer and never claims the consumer slot.
`close()` unmaps and closes the fd; nothing unlinks the name afterwards,
so a stale mapping is detected by identity, not by absence.

Fixed formats: the driver is 44.1 kHz float32 stereo
(`Driver/src/DriverFormat.h`: `kApm44DriverSampleRate` 44100,
`kApm44DriverChannelCount` 2, two mono lanes `kApm44DriverStreamCount`).
The shm ring is 44100 Hz stereo (`ShmRingLayout.h`: `kShmSampleRate`, `kShmChannels`).
The daemon converts 44100 Hz in to 48000 Hz out
(`Shared/include/apm44/AudioFormats.h`: `kInputSampleRate`, `kOutputSampleRate`).
`BridgeDaemon/src/hal/FormatNegotiator.cpp` checks the devices with a 1 Hz
nominal-rate tolerance: in HAL mode `negotiateVirtualOutput` requires a
float32 stereo output at 48000 Hz; in BlackHole mode `negotiate` also
requires the 44100 Hz input.

## 2. The shm ring

Layout (`ShmRingLayout.h`): name `/apm44_bridge_ring` (`kShmRingName`),
magic `kShmMagic`, version `kShmVersion` (4), default capacity
`kDefaultShmCapacityFrames` (8192 frames, room for a full 4096-frame
Core Audio burst plus headroom), interleaved float stereo samples after
a 64-byte-aligned header, 64-byte `producer_build_id` (`kShmBuildIdBytes`).

Producer: the driver IO handler.
`Driver/src/ShmIoHandler.cpp` / `OnProcessMixedOutput` pushes stereo
interleaved blocks (`pushInterleaved`) and re-interleaves pairs of mono
lane blocks (`pushMonoLane`, `flushPendingLanes`).
Until the daemon signals ready, frames are dropped and counted
(`producer_not_ready_dropped_frames`).
The ring stays mapped across `OnStopIO` so the daemon survives
transport stop/start.

Consumer: the daemon feed. `VirtualDeviceFeed.cpp` / `drainTo` pops shm
into the engine smoothing ring inside the output IOProc. `markReady`
sets `daemon_ready` (`Shared/src/MmapShmRing.cpp` /
`MmapShmRing::setDaemonReady`; only the owning consumer may set it).
Only one live consumer may hold the ring (`claimConsumer`, else
`ConsumerBusy`).

Readiness and identity checks: `ShmRingLayout.h` / `ValidateShmHeader`
(magic, version, header size, channels, rate, build id) and
`ShmObjectIdentity.h` / `ShmObjectIdentityChanged` (dev/inode, size,
driver generation).

"Stale ring" means the mapped object no longer matches the live one:
`MmapShmRing::isMappedObjectStale` returns true when the name is gone
or dev/inode, size, or generation changed.
`VirtualDeviceFeed.cpp` / `pollStaleRing` returns `Ok` when the feed is not
open or the mapping is not stale. When it is stale it closes and re-opens:
a live new object is `Remapped`; a failed open or a still-stale mapping is
`MustExit`.
`BridgeDaemon/src/engine/StaleRingRecoveryPlan.h` / `PlanStaleRingRecovery`
decides:

| Poll result | Action | Output IO restarts |
|---|---|---|
| `Ok` | `None` | yes |
| `Remapped`, SRC epoch reset ok | `StopForRemap` (log, keep running) | yes |
| `Remapped`, epoch reset failed | `StopForExit` | no |
| `MustExit` | `StopForExit` (exit 42) | no |

Startup build mismatches are debounced, not instant:
`BridgeDaemon/src/engine/ShmMismatchDebounce.h` / `ShmMismatchDebounce`
fails only after 3 identical consecutive `ProducerBuildMismatch`
observations, so a half-published header mid-`create()` cannot stick
the daemon with exit 44.

Real-time rules (`Shared/include/apm44/RtConstraints.h`,
`CONTRIBUTING.md`): IOProc threads must not allocate, lock, log, do
file/network IO, enumerate devices, or message Swift/Obj-C. Setup runs
before `AudioDeviceStart`. The IOProcs (`IoProcHandlers.cpp` /
`InputIoProc`, `OutputIoProc`) copy through preallocated scratch and call
`onInput`/`onOutput`, which drain, servo, resample and fade without
allocating.

The prebuffer gate (`VirtualPrebufferGate.h` / `VirtualPrebufferGate`)
holds output silent until the fill reaches target (`shouldOutput`); any
starvation calls `forceRebuffer` and playback waits again.

## 3. The daemon

Startup (`BridgeDaemon/src/main.cpp` / `main`): parse CLI, serve the
info verbs early, acquire the singleton lock, optionally watch the
parent, resolve devices (`ResolveDevices`), negotiate formats
(`NegotiatePair`), convert options (`CliOptions.cpp` /
`ToEngineOptions`), `prepare`, `start`, then `runUntilSignal`. In virtual mode its per-tick callback
polls the stale ring (`BridgeEngine.cpp` / `pollVirtualFeedStaleRing`);
in either mode it prints a metrics JSON line per tick only when
`--metrics-json` is set.

`prepare` (`BridgeEngine.cpp` / `BridgeEngine::prepare`): in virtual
mode it polls for the shm ring every 100 ms for up to 15 s, floors the
target fill at `kHalTargetFillFloorMs` (20 ms), sizes the smoothing ring,
resets `DriftController`
(target fill, 3000 ppm virtual max via `kVirtualDeviceMaxPpm`,
else `DriftController::kMaxPpm` 500), prepares `LibSamplerateSrc`,
then `markReady`. `BridgeEngine::effectiveTargetFillMs()` returns the
value `prepare` planned with, set at its start even if `prepare` later
fails. The metrics line's `target_fill_ms` (`main.cpp`) and the startup
log report that value, not the requested `--target-fill-ms`. The app
keeps its own copy of the floor (`LatencyPreset.swift`).

`start` (`BridgeEngine.cpp` / `BridgeEngine::start`): requests 512-frame
device buffers (`kRequestedBufferFrameSize`, restored on stop via
`DeviceBufferLease`), creates the output IOProc (plus input IOProc in
BlackHole mode), starts the devices. `stop` tears IOProcs down,
restores buffer sizes, and closes the feed.

`BridgeControlLoop.h` sets the tick to `kControlLoopInterval` (500 ms)
and caps callback chunks at `kMaxCallbackFrames` (1024 frames).
`onInput` pushes into the smoothing ring, dropping the tail on overrun.
In virtual mode `onOutput` drains shm and gates on the prebuffer; in both
modes it then servos the SRC ratio (`DriftController::update`), resamples,
and fades 64 frames
(`kUnderrunFadeFrames`) across gaps instead of clicking. Metrics publish
from the output thread each call (`engine/MetricsPublisher.h` /
`PublishMetrics`, `ReadMetrics`). (`onInput`/`onOutput`:
`BridgeEngine.h` / `BridgeEngine`.)

Stop: `SIGINT`/`SIGTERM` (and parent stdin EOF) set the flag via
`BridgeEngine::requestStop`; `runUntilSignal` exits the loop, calls
`stop()`, and prints a final summary to stderr. The flag
(`BridgeEngine.cpp` / `gStopRequested`) is a lock-free `std::atomic<bool>`
(`static_assert`ed always lock-free), so the signal handler, the
parent-death watcher thread and the main thread's reads in `prepare` and
`runUntilSignal` do not race.

## 4. Daemon exit codes

Built from `BridgeDaemon/src/DaemonExitCodes.h` and `main.cpp`.
The app mirrors them in `BridgeProcessPolicy.swift` / `DaemonExitCode`
and classifies in `BridgeTerminationPolicy` / `classify`
(tested in `tests/test_bridge_process_policy.swift`).
`classify` reads only the integer status
(`ProcessLaunching.swift` / `terminationStatus`); there is no
signal-specific branch.

| Code | When the daemon returns it | App outcome (`BridgeTerminationOutcome`) and banner |
|---|---|---|
| 0 | `--help`/`--version`/list/preflight/print-config/shm-status success, clean run to stop | running + 0: `cleanExitWhileRunning`, back to idle silently. starting + 0: `failWhileStarting`, error with stderr tail |
| 1 (`kExitFailure`) | Device resolve/negotiate failure, `prepare` failure (except virtual build mismatch), `start` failure, unusable lock file, preflight/print-config failure | running (stop not by user): `autoRetry`, "Reconnecting… (attempt n of 4)". user stop race: `failWhileRunning`. starting: `failWhileStarting`. Error kind comes from `DaemonStderrTail` / `failure(exitStatus:)`: `driverIPCFailed` when the exit is 42, or, as a fallback, stderr mentions "shm"; else `helperFailed` with the last stderr line verbatim (none: generic start failure) |
| 2 | CLI usage errors (`CliOptions.cpp` exits 2 on bad `--target-fill-ms`/`--src-quality`); `--shm-status` when the ring object is missing | Same generic nonzero path as 1 (no `DaemonExitCode` match) |
| 3 | `--shm-status` when the ring fails for any other reason | Same generic nonzero path as 1 |
| 42 (`kExitStaleShmRing`) | Any `StopForExit` from the stale-ring poll: the ring could not be remapped, the SRC epoch reset failed, or stopping/restarting output IO failed | running, not a user stop: `autoRetry` (retried like 1). User stop: `failWhileRunning`. starting: `failWhileStarting` |
| 43 (`kExitSingletonBusy`) | Singleton lock held by another process (`ExitCodeForSingletonFailure`) | `helperAlreadyRunning`, `failWithoutRetry`: error, no retry, banner names the rival helper (`AppStrings.swift` / `helperAlreadyRunning`) |
| 44 (`kExitLoadedDriverBuildMismatch`) | Virtual-mode prepare saw a real producer build mismatch (`ExitCodeForPrepareFailure`) | `loadedDriverMismatch`, `failWithoutRetry`: error, no retry, banner says Core Audio still runs an older driver (`AppStrings.swift` / `loadedDriverBuildMismatch`) |

Exhaustion replaces the reconnecting banner with the
"stopped after 4 unstable launches" message (section 6).
The app carries errors as a typed `BridgeError`
(`BridgeErrorPresentation.swift`), never as rendered text.
`BridgeError.message`, `headline`, `recovery` and `diagnostic`, and
`BridgeErrorPresentation.presentation(for:)` on top of them, derive the
localized sentence, short headline, recovery guidance and Details text
from the kind and its raw payload (build IDs, exit status, stderr).

## 5. The app's run-state machine

States (`BridgeProcessManager.swift` / `BridgeRunState`):
`idle`, `starting`, `running`, `stopping`, `reconnecting`, `error(BridgeError)`.
`isRunning` is true only for `running`; `isTransitioning` covers
`starting`/`stopping`. Stop reasons (`StopReason`): `user`,
`settingsChange`, `hotplug`, `internal`.

| State | Meaning |
|---|---|
| `idle` | No child. Only state (with `error`, `reconnecting`) `start` accepts |
| `starting` | The launch call is in progress (brief) |
| `running` | Set as soon as the launch returns; metrics may be absent, flowing, or stale |
| `stopping` | SIGTERM sent, waiting for the child (escalates to SIGKILL) |
| `reconnecting` | Retry wait or parked for a missing device; startable again |
| `error(BridgeError)` | Terminal error kind; Start retries from here |

Transitions:

- `start` (idle/error/reconnecting only): resets the retry budget,
  gates on binary present, output selected, HAL build ids matching
  when the HAL device is present (`HalDriverDetector.swift` /
  `buildIDsMatch`, missing ids fail closed), output
  alive and compatible; then `starting` to `running`. Anything blocked
  becomes `error`.
- `stop` / `stopAsync`: `user` stop, `stopping`, escalate
  (TERM, 5 s wait, KILL, 5 s wait), then `idle`.
- `quitApplication` (`MenuFooterViews.swift` quit button): stop, then
  terminate the app.
- `restart(reason)`: stop then start; concurrent requests coalesce via
  `restartTask`/`pendingRestartReason` (one extra launch, never two).
  From `error` it just starts; from `idle` it does nothing. Settings
  changes (`MenuControlCard.swift` calls `restartForSettingsChange`)
  mark `isApplyingSettings` and restart with `.settingsChange`.
- Unexpected exit (`handleTermination`): `stopping` goes `idle`;
  running + 0 goes `idle`; running + nonzero (non-user) schedules a
  retry (`reconnecting`); 43/44 fail at once; starting + anything fails.
- Hotplug (`HotplugMonitor.swift` / `HotplugMonitor`, 1 s debounce,
  wired in `APM44BridgeApp.swift` to `handleHotplug`): a changed output
  restarts (`.hotplug`); a gone output records resume intent, stops the
  helper, then settles in `reconcileAfterOutputLossStop` from the current
  state and device list, not the list that triggered the stop: it
  relaunches once if the selected output is back, else parks
  `reconnecting` ("waiting for output"), and leaves the state alone after
  a newer user stop, sleep or other owner; a returning output restarts;
  `idle` refreshes.
- Sleep/wake (`SystemLifecycleMonitor.swift` / `SystemLifecycleMonitor`
  to `handleSystemWillSleep`/`handleSystemDidWake`): sleep records a
  resume intent when active and stops the child; wake waits out an
  in-flight stop (11 s), refreshes devices, restarts when the output is
  alive and compatible, else parks `reconnecting`. `performRestart` and
  the hotplug output-loss paths compare `systemSleepGeneration` and
  `userStopGeneration` after their stop wait, so a user stop cancels the
  relaunch and a sleep leaves it to the wake; the wake checks
  `systemSleepGeneration` after its refresh and re-reads
  `resumeAfterSystemWake`, which a user stop clears.
  See `docs/adr/0001-wake-resume-intent.md`: the resume intent
  (`resumeAfterSystemWake` plus `wasRunningBeforeDisconnect`) must
  survive every `await` in the wake path; a superseded device refresh
  joins the newest refresh instead of failing; a user stop cancels a
  pending wake resume.
- Post-update resume: Sparkle install posts a notification while
  running; `resumeAfterUpdateIfRequested` restarts within 10 minutes
  when idle/error/reconnecting with the output enumerated. The
  stale-output watch (`scheduleStaleWatch`) sets `metricsStale` when more
  than 2 s pass after the last metrics sample (checked every 0.5 s; before
  the first sample it stays false;
  `BridgeEnvironment.swift` / `BridgeTiming`); UI-only, never restarts.
  Rising frame loss flashes a glitch indicator (2 s).

## 6. Retry policy

`BridgeProcessPolicy.swift` / `BridgeRetryBudget`
(expected behavior in `tests/test_bridge_retry_budget.swift`):

- `maxUnhealthyLaunches` is 4. `consumeAttempt` bumps the counter and
  returns `retry(delay)` picking `delays[min(attempt-1, last)]`, so
  short tables clamp to their final element; the 4th unexpected exit
  returns `exhausted` with last exit status and stderr tail. Live cadence
  (`BridgeEnvironment.swift` / `BridgeTiming.live`): the delay table is
  1, 2, 4, 4 s, so the app relaunches after 1, 2 and 4 s and the fourth
  exit ends in the exhausted banner; stability window 15 s; stale check
  0.5 s; stale after 2 s; glitch flash 2 s.
- The window resets the budget: first metrics move health to
  handshaking; 15 s of stable running calls `reset`, clearing counter
  and diagnostics. A fresh user `start` also resets.
- A user `stop` clears the counter but keeps diagnostics
  (`clearAttemptKeepingDiagnostics`).
- Retried: any nonzero exit while running whose stop was not the user
  (codes 1, 2, 42 and friends). Never retried (`failWithoutRetry`,
  counter cleared): 43 and 44. Starting-state exits fail at once.

### Resolved gaps

Earlier revisions of this section listed two gaps. Both are fixed; the
history is kept so a change does not reintroduce them.

- The stop wait could not time out. `waitForTermination` raced the
  termination against a timer in a task group whose continuation child
  ignored cancellation, so a helper that never exited after SIGTERM left
  the app in `stopping` and SIGKILL was never reached. Now each waiter
  registers under its own id (`terminationWaiters`) with its own timer
  (`terminationWaiterTimers`) that removes it and resumes it with failure,
  so the wait throws `timedOut` even if the process never exits, and
  `finishStopWithEscalation` reaches SIGKILL. The 11 s wake wait uses the
  same path. Tests in `tests/test_bridge_process_manager.swift`:
  `testStopEscalatesToSigkillWhenHelperIgnoresSigterm`,
  `testStopReturnsWhenHelperSurvivesSigkill`,
  `testWakeParksWhenSleepStopNeverFinishes`,
  `testConcurrentTerminationWaitersAllComplete`.
- A second sleep during a wake's refresh dropped the resume intent.
  `handleSystemDidWake` now consumes `resumeAfterSystemWake` only at the
  end and first checks `systemSleepGeneration`; a sleep that landed
  meanwhile keeps the flag for the next wake. Tests:
  `testSecondSleepDuringWakeRefreshKeepsResumeIntent`,
  `testSleepDuringIdleWakeRefreshDefersResumeToNextWake`.

Also fixed by the 2026-09-29 architecture audit findings A001, A002 and
A003: a hotplug that saw the output return during the loss stop was
dropped (`reconcileAfterOutputLossStop`;
`testOutputReturningDuringLossStopRelaunchesOnce`,
`testOutputStayingAbsentDuringLossStopParksWaiting`,
`testUserStopDuringLossStopDoesNotRelaunchWhenOutputReturned`,
`testUserStopDuringLossStopIsNotOverwrittenByWaitingPark`,
`testSelectionChangedDuringLossStopLaunchesOnlyNewSelection`); the helper
stop flag was a non-atomic `volatile sig_atomic_t` (`gStopRequested`;
`tests/test_engine_prepare_stop.cpp`, "the parent-death watcher stops the
running control loop promptly"); and metrics reported the requested rather
than the effective target fill (`effectiveTargetFillMs`; "metrics report
the HAL floor a virtual-device engine prepared with").

### Known gaps

No defect is recorded against the run-state machine at this revision.
Open test gaps, not known defects: a settings change during a user stop,
and a device-change restart together with a settings restart (T14 and
T15, listed in `docs/adr/0001-wake-resume-intent.md`), have no test named
for them. The unit tests use fake launchers and device sources, so real
sleep/wake and USB hotplug timing is not covered.

## 7. Updates and install

In-app updates use Sparkle: `SparkleUpdateController.swift`
(`SPUStandardUpdaterController`) owns update state and
`UpdateActivationCoordinator.swift` fronts the update UI. Installing
while running posts the notification behind the post-relaunch resume
(section 5). The PKG preinstall inlines
`scripts/lib/apm44-stop-running.sh` / `apm44_stop_app_and_helper`
(quit app, TERM/KILL app and helper), then moves the installed app and
driver to `/Library/Application Support/APM44 Bridge/InstallBackup`.
The postinstall checks the new pair. If a check fails, it moves the
backup back; if all pass, it deletes the backup. Either way it restarts
Core Audio (`scripts/build-release-pkg.sh`). See `docs/release.md` and
`docs/install.md`.

## 8. Where to look

| Concern | Files | Tests |
|---|---|---|
| Shm ring, header, identity | `Shared/include/apm44/ShmRingLayout.h`, `MmapShmRing.h`, `ShmObjectIdentity.h`, `Shared/src/MmapShmRing.cpp` | `tests/test_mmap_shm_ring.cpp`, `tests/test_mmap_shm_validation.cpp`, `tests/test_shm_object_identity.cpp` |
| Driver device and producer | `Driver/src/Driver.cpp`, `DriverFormat.h`, `ShmIoHandler.h`, `ShmIoHandler.cpp` | `tests/test_shm_io_handler.cpp`, `tests/test_hal_driver_contract.cpp` |
| Engine, SRC, drift, IOProcs | `BridgeDaemon/src/engine/BridgeEngine.h`, `BridgeEngine.cpp`, `LibSamplerateSrc.h`, `IoProcHandlers.h`, `IoProcHandlers.cpp`, `BridgeControlLoop.h` | `tests/test_lib_samplerate_src.cpp`, `tests/test_drift_controller.cpp`, `tests/test_io_proc_callbacks.cpp`, `tests/test_control_loop_wait.cpp`, `tests/test_input_frame_demand.cpp`, `tests/test_planar_ring_buffer.cpp` |
| Virtual feed and stale recovery | `BridgeDaemon/src/engine/VirtualDeviceFeed.h`, `VirtualDeviceFeed.cpp`, `StaleRingRecoveryPlan.h`, `ShmMismatchDebounce.h`, `VirtualPrebufferGate.h` | `tests/test_virtual_device_feed.cpp`, `tests/test_virtual_prebuffer_gate.cpp`, `tests/test_shm_stale_recovery.cpp` |
| Daemon CLI, exits, metrics | `BridgeDaemon/src/main.cpp`, `CliOptions.h`, `CliOptions.cpp`, `DaemonExitCodes.h`, `ProcessSingletonLock.h`, `ParentDeathWatch.h`, `engine/BridgeMetrics.h`, `engine/MetricsPublisher.h` | `tests/test_daemon_exit_codes.cpp`, `tests/test_daemon_exit_codes.sh`, `tests/test_bridge_metrics_json.cpp`, `tests/test_audio_formats.cpp` |
| App launch, states, retry | `App/APM44Bridge/BridgeProcessManager.swift`, `BridgeProcessPolicy.swift`, `BridgeEnvironment.swift`, `MetricsParser.swift`, `BridgeErrorPresentation.swift`, `ProcessLaunching.swift` | `tests/test_bridge_process_manager.swift`, `tests/test_bridge_process_policy.swift`, `tests/test_bridge_retry_budget.swift`, `tests/test_metrics_parser.swift`, `tests/test_setup_and_error_presentation.swift` |
| Devices, hotplug, sleep, HAL gate | `App/APM44Bridge/HotplugMonitor.swift`, `SystemLifecycleMonitor.swift`, `HalDriverDetector.swift`, `DeviceCatalog.swift`, `BridgeStartReadiness.swift`, `DriverMaintenance.swift` | `tests/test_system_lifecycle_monitor.swift`, `tests/test_device_catalog.swift`, `tests/test_verify_devices.sh` |
| Settings and presentation | `App/APM44Bridge/BridgeSettings.swift`, `LatencyPreset.swift`, `SrcQuality.swift`, `MenuControlCard.swift`, `APM44BridgeApp.swift` | `tests/test_latency_preset.swift`, `tests/test_bridge_start_readiness.swift`, `tests/test_menu_presentation.swift` |
| Updates and packaging | `App/APM44Bridge/SparkleUpdateController.swift`, `UpdateActivationCoordinator.swift`, `scripts/build-release-pkg.sh`, `scripts/lib/apm44-stop-running.sh` | `tests/test_sparkle_updater.swift`, `tests/test_update_error_policy.swift`, `tests/test_release_scripts.sh`, `tests/test_appcast.sh`, `tests/test_e2e_scripts.sh` |
