---
status: fixed_pending_user_confirmation
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

- hypothesis: ShmIoHandler pairs mono lanes by exact HAL output timestamp, and the two stream callbacks can straddle libASPL's one-second zero-timestamp boundary, dropping one stereo block per second.
- test: add a regression test where left/right mono lanes for one cycle arrive with different timestamps; current code should fail by not pushing a stereo block.
- expecting: failing test proves the lane aggregation logic is too strict and the fix is to pair adjacent stream lanes by channel completion rather than exact timestamp.
- next_action: verify fixed lane pairing with targeted tests, rebuild, reinstall matching driver, and confirm live shm/HAL status.
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

## Eliminated

- hypothesis: The click is caused only by the daemon's internal drift/output path.
  evidence: A targeted driver-side test reproduces a dropped block in `ShmIoHandler` without involving the daemon.

## Resolution

- root_cause: `ShmIoHandler` paired two mono HAL output lanes using exact output timestamp equality. Around libASPL's one-second zero-timestamp period boundary, adjacent lane callbacks can carry different timestamp values, causing the handler to discard one lane and drop one stereo block roughly once per second.
- fix: Pair mono lanes by channel completion instead of exact timestamp; reset pending partial audio when frame count changes or when the same channel repeats before the opposite channel arrives.
- verification: Failing rollover regression test now passes; full build, CTest, CI, HAL verification, installed hash check, and shm status all pass.
- files_changed: `Driver/src/ShmIoHandler.{h,cpp}`, `tests/test_shm_io_handler.cpp`, `.planning/debug/click-each-second-dropout.md`
