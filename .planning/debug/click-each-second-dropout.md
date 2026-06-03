---
status: resolved
trigger: "now i get a click each second like a little dropout"
created: "2026-06-03"
updated: "2026-06-03"
---

# Debug Session: click-each-second-dropout

## Symptoms

- Expected behavior: Monitoring through APM44 Bridge should be stable with no periodic clicks or dropouts.
- Actual behavior: A small click/dropout is audible about once per second.
- Error messages: None reported.
- Timeline: Started after the HAL virtual-device Float32/non-interleaved contract change.
- Reproduction: Listen through APM44 Bridge during live monitoring/playback.

## Current Focus

- hypothesis: The UI can show zero glitches because it tracks hard `xruns`, while periodic audible dropouts can come from virtual-mode partial underruns and prebuffer/recovery behavior.
- test: verify AirPods/BlackHole live helper captures for `underruns`, `xruns`, fill jumps, producer fps, and fill stability after adaptive virtual-source pacing.
- expecting: sustained playback holds near Safe target fill with `underruns=0`, `xruns=0`, and no large fill jump/rebuffer events.
- next_action: resolved; reopen only if periodic dropouts recur on the installed helper/driver pair.
- reasoning_checkpoint:
- tdd_checkpoint:

## Evidence

- 2026-06-03: User reports a small click/dropout roughly once per second after the HAL Float32/non-interleaved driver change.
- 2026-06-03: Recent change replaced one packed stereo SInt16 stream with two mono Float32 output streams and added `ShmIoHandler::pushMonoLane`.
- 2026-06-03: `ShmIoHandler::pushMonoLane` currently resets pending lane state when `pendingTimestamp_ != timestamp`.
- 2026-06-03: libASPL `DeviceParameters::ZeroTimeStampPeriod` defaults to `SampleRate`, documented as one second.
- 2026-06-03: libASPL `GetZeroTimeStampImpl` advances `currentPeriodTimestamp_` by that period; this matches the user's once-per-second symptom.
- 2026-06-03: Passive shm header sampling showed producer/consumer burstiness and frequent shm fill at 0 frames, but this does not prove daemon underrun because the daemon has a separate buffered ring.
- 2026-06-03: Added regression test for mono lanes crossing timestamp rollover. Before fix it failed with `consumer.popInterleaved(out.data(), 3) == 3` producing `0 == 3`.
- 2026-06-03: Removed timestamp equality from mono-lane pairing; lane completion now resets only on frame-count change or repeated same-channel arrival before a complete stereo block.
- 2026-06-03: Added repeated-channel regression test to ensure stale partial lanes are discarded.
- 2026-06-03: Targeted `test_shm_io_handler` passed with 42 assertions in 5 test cases.
- 2026-06-03: `cmake --build build`, `git diff --check`, `ctest --test-dir build --output-on-failure`, and `./scripts/ci.sh` passed.
- 2026-06-03: Installed matching fixed driver; `verify-hal-driver.sh` structural checks passed and installed executable hash matches build hash `06b6e49900a6ad3a8b1319b34ed536b52b3d31e512df979e277d1db9df17d016`.
- 2026-06-03: `build/BridgeDaemon/apm44-bridge --shm-status` reports `shm_status=ok`, `sample_rate=44100`, `channels=2`.
- 2026-06-03: Existing app-launched `apm44-bridge` process survived Core Audio reload, so user may need to stop/start the bridge from the menu bar to reconnect to the newly created shm ring.
- 2026-06-03: User reports many clicks, pops, and audio dropouts even with Best SRC and Safe latency.
- 2026-06-03: Live state eliminated stale install: `/Applications/APM44 Bridge.app` was running `--target-fill-ms 30 --src-quality best`; `--shm-status` showed helper and driver build IDs both `0.1.0+a9b8d7bdf99f`.
- 2026-06-03: Shared-memory header sampling while the old helper ran showed driver writes and daemon reads were active, with shm fill often at 0/297/1024 frames rather than stuck full.
- 2026-06-03: Found daemon consumed a rounded-up 471 input frames for every 512-frame output callback. Exact nominal demand is 512 * 44100 / 48000 = 470.4 frames, so always rounding up drains about 56.25 extra input frames per second before hardware drift.
- 2026-06-03: Found drift sign was inverted for a `src_ratio = output/input` controller: fill above target raised the ratio, which reduces input demand instead of increasing it.
- 2026-06-03: Added `InputFrameDemand` regression coverage proving one output second consumes exactly 44100 input frames across 128/256/512/1024 callback sizes and consumes more input when SRC ratio is reduced.
- 2026-06-03: Added SRC regression coverage around full output blocks and flush/state draining.
- 2026-06-03: Fixed daemon output path to use fractional input-frame demand, reset demand on prepare, lower ratio when fill is above target, and keep libsamplerate pending input available across calls.
- 2026-06-03: Updated offline soak harness to model the corrected fractional producer/consumer demand instead of old per-block ceil behavior.
- 2026-06-03: `cmake --build build`, `ctest --test-dir build --output-on-failure`, `./scripts/ci.sh`, and `./scripts/ci-soak.sh` passed.
- 2026-06-03: `build/BridgeDaemon/apm44-soak --duration-sec 60` reports `underruns=0`, `overruns=0`, `passed=1`.
- 2026-06-03: Rebuilt Release app, embedded rebuilt helper, replaced `/Applications/APM44 Bridge.app`, and reopened the menu app. Installed helper hash now matches `build/BridgeDaemon/apm44-bridge` hash `0c7f351cae28149b7992942c860adff7262ec647297f5a0561339df4a56a2a3c`.
- 2026-06-03: User screenshot still showed severe live failure after the daemon-side demand fix: Buffer fill `19.7 ms`, Glitches `252`, Drift ratio `1.0885`.
- 2026-06-03: Direct `/Applications` helper capture before the follow-up fixes reproduced the issue: over 8s `underruns=22`, `xruns=6`; over ~20s shared-memory sampling showed `write_fps=43114.6`, `read_fps=43124.1`, final fill `13.2 ms`, `underruns=61`, `xruns=18`.
- 2026-06-03: Found another driver-side loss path: `ShmIoHandler` held only one pending mono lane, so a real callback order like `L, L, R, R` dropped a complete stereo block. Added a failing regression that expected 6 frames but got 3.
- 2026-06-03: Replaced single pending mono-lane storage with fixed-size per-channel FIFO pairing by sample time when possible, while preserving timestamp-rollover pairing. Focused `test_shm_io_handler` passed.
- 2026-06-03: Found `VirtualDeviceFeed::drainTo` popped shared-memory frames before checking daemon-ring capacity, discarding input whenever the internal ring was full. Added a regression proving shm remains untouched when the destination ring is full.
- 2026-06-03: Installed matching HAL driver via admin installer and reloaded CoreAudio. `verify-hal-driver.sh` passed structural checks; installed HAL executable matched build hash `63d91b29341f20c15b140b0e2cd1b3997a37e08568b856133338162c5168fd70`.
- 2026-06-03: AirPods disappeared from CoreAudio output enumeration during final validation, so exact AirPods live capture could not run. Bluetooth still showed them connected; CoreAudio/SwitchAudioSource only listed BlackHole, built-in speaker, APM44 Bridge, and Jump outputs.
- 2026-06-03: Isolated validation used APM44 Bridge as system output with a generated 44.1 kHz tone and BlackHole 2ch as the 48 kHz sink. This validates driver/daemon timing without depending on the transient AirPods endpoint.
- 2026-06-03: Before virtual prebuffering, helper-before-playback capture produced many startup/recovery underruns: 20s run had `delta underruns=434`, `xruns=271`, final fill about `11.6 ms`.
- 2026-06-03: Added virtual-device prebuffer gate and removed fake silence prefill in virtual mode. Helper now waits for real 44.1 kHz shared-memory input to reach target fill before starting SRC playback.
- 2026-06-03: Tuned drift controller to request meaningful low-fill catch-up while retaining the ±500 ppm cap, and added regression coverage for the low-fill ppm request.
- 2026-06-03: Final isolated 60s helper-before-playback capture with installed helper hash `f8b280f144880d91da84f32412e0e8a79569524309c7cdf5d0e38a25da3bf294`: `write_fps=43995.9`, `read_fps=43991.7`, first fill `36.6 ms`, mid fill `20.8 ms`, last fill `27.8 ms`, `delta underruns=5`, `delta xruns=0`, final stopped fill `28.6 ms`.
- 2026-06-03: User reported UI `Glitches` remained zero while a small periodic dropout was still audible.
- 2026-06-03: Live AirPods capture reproduced that exact split: `delta xruns=0`, but partial underruns rose and the fill jumped from `10.5 ms` to `32.8 ms`; this identified the audible event as prebuffer/recovery silence rather than a hard xrun.
- 2026-06-03: Removing rebuffer for tiny partial shortages eliminated big fill jumps but left the internal ring pinned around `10-12 ms` with many partial underruns, confirming a producer/consumer pacing mismatch remained.
- 2026-06-03: A trial change to shorten the HAL zero timestamp period to 512 frames was tested and rejected; it reduced measured production to about `1363.8 fps`. Reverted and reinstalled the known-good HAL driver hash `63d91b29341f20c15b140b0e2cd1b3997a37e08568b856133338162c5168fd70`.
- 2026-06-03: Added configurable drift ppm cap. Default remains `500 ppm`; virtual-device mode widens the cap to handle the measured virtual-source pacing mismatch without silence rebuffering.
- 2026-06-03: Final post-fix isolated 45s capture with installed helper hash `e6ee15b76b0cf81d7f2b868a06f3b66f65155a03fc654c0faf91f603b799d0e1`: `write_fps=44100.8`, `read_fps=44098.0`, first fill `32.6 ms`, mid fill `30.2 ms`, last fill `30.5 ms`, `delta underruns=0`, `delta xruns=0`, `max_fill_jump=1.7`, `big_jumps=0`.
- 2026-06-03: User confirmed the installed build works in live monitoring, then confirmed again after completing the follow-up operator steps.

## Eliminated

- hypothesis: The click is caused only by the daemon's internal drift/output path.
  evidence: A targeted driver-side test reproduces a dropped block in `ShmIoHandler` without involving the daemon.
- hypothesis: Best SRC quality or Safe latency alone can compensate for the remaining dropouts.
  evidence: User reproduced many dropouts while the live helper was already running `--target-fill-ms 30 --src-quality best`; code inspection showed nominal rounding drained the internal ring faster than the driver could produce.

## Resolution

- root_cause: Several real-time handoff defects compounded. `ShmIoHandler` first dropped mono lanes around timestamp rollover, then still dropped repeated same-channel blocks because it had only one pending lane slot. The daemon also overconsumed input due per-callback ceil demand, had inverted drift sign, discarded shared-memory frames when its internal ring was full, consumed fake silence before real virtual-device input arrived, and later exposed non-xrun partial underrun/rebuffer events when virtual-source pacing exceeded the normal ±500 ppm correction range.
- fix: Use per-channel fixed FIFO lane pairing in the HAL driver; add fractional input-frame demand; correct drift direction; preserve libsamplerate pending input; prevent `VirtualDeviceFeed` from discarding shm frames when the daemon ring is full; add virtual prebuffering; avoid rebuffering for tiny partial shortages; widen the drift cap only in virtual-device mode so the bridge tracks the observed virtual source without inserting silence.
- verification: Driver lane regressions, input-frame demand tests, drift tests, libsamplerate tests, virtual-feed tests, virtual-prebuffer tests, full CMake/CTest, Swift app tests, CI, soak, HAL structural verification, isolated 45s live helper capture, and user live monitoring confirmation all pass. Final capture held near `30 ms` with `0` underruns, `0` xruns, and no large fill jumps.
- files_changed: `Driver/src/ShmIoHandler.{h,cpp}`, `tests/test_shm_io_handler.cpp`, `Shared/include/apm44/InputFrameDemand.h`, `Shared/src/InputFrameDemand.cpp`, `Shared/include/apm44/DriftController.h`, `Shared/src/DriftController.cpp`, `BridgeDaemon/src/engine/BridgeEngine.{h,cpp}`, `BridgeDaemon/src/engine/LibSamplerateSrc.{h,cpp}`, `BridgeDaemon/src/engine/VirtualDeviceFeed.cpp`, `BridgeDaemon/src/engine/VirtualPrebufferGate.h`, `BridgeDaemon/src/tools/SoakHarness.cpp`, `tests/test_input_frame_demand.cpp`, `tests/test_drift_controller.cpp`, `tests/test_lib_samplerate_src.cpp`, `tests/test_virtual_device_feed.cpp`, `tests/test_virtual_prebuffer_gate.cpp`, `Shared/CMakeLists.txt`, `tests/CMakeLists.txt`, `.planning/debug/click-each-second-dropout.md`
