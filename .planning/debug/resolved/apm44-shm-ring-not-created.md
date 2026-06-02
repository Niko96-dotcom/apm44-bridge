---
status: resolved
trigger: "Menu app starts bridge helper in driver mode, helper waits for /apm44_bridge_ring and times out even after explicitly starting APM44 Bridge CoreAudio device with an IOProc probe."
created: "2026-06-02T21:10:31Z"
updated: "2026-06-02T21:23:15Z"
---

# Debug Session: APM44 shm ring not created

## Symptoms

- expected_behavior: "APM44 Bridge menu app can launch the helper in virtual-device mode; the helper connects to the HAL driver's shared-memory ring and bridges DAW output from 44.1 kHz to AirPods at 48 kHz."
- actual_behavior: "The helper prints 'Waiting for APM44 Bridge shm...' and eventually fails with 'could not open shm ring (is APM44Bridge.driver IO running?)' and 'engine prepare failed'."
- error_messages: "Waiting for APM44 Bridge shm...; error: could not open shm ring (is APM44Bridge.driver IO running?); error: engine prepare failed"
- timeline: "Observed 2026-06-02; installed helper was newer than the loaded installed driver, and installed driver differed from repo build/staging binaries."
- reproduction: "Start the menu app in driver mode, or explicitly start the APM44 Bridge CoreAudio device with a small IOProc probe; /apm44_bridge_ring never appears."

## Current Focus

- hypothesis: "The current raw POSIX shm path can fail silently inside the AudioServerPlugIn host, be masked by app/driver version drift, or be clobbered by local tests that use the production shm name; the repo needs diagnostics, test isolation, and install-time verification that the installed driver creates a reachable ring."
- test: "Instrument shm create/open failures, add version/build identity into the ring, add install/start verification, and run unit/CI checks."
- expecting: "Failures identify the exact driver-side errno or mismatch; a freshly installed matching driver/app pair creates /apm44_bridge_ring before the helper times out."
- next_action: "Patch shm diagnostics and installation verification."
- result: "Installed driver now matches build and creates a readable shm ring with matching driver/helper build IDs."
- reasoning_checkpoint: "Apple QA1811 says AudioServerPlugIns run in a limited sandboxed host and must declare Mach services for IPC; libASPL notes shared memory can be used but the plug-in remains sandboxed."
- tdd_checkpoint: "Not yet started."

## Evidence

- 2026-06-02T21:10:31Z: "Driver ShmIoHandler constructor calls ensureRingReady(), but create failures are silent and the helper only polls for 120 seconds."
- 2026-06-02T21:10:31Z: "Driver/Info.plist.in has AudioServerPlugIn_MachServices present but empty; current transport is raw POSIX shm."
- 2026-06-02T21:10:31Z: "MmapShmRing::create() unlinks and creates /apm44_bridge_ring with mode 0666, but exposes no errno/status to driver logs or helper diagnostics."
- 2026-06-02T21:21:41Z: "Installed /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver executable hash now matches build/Driver/APM44Bridge.driver: 4246ead3e867f767adcc23feab4e335d27a30702b8469d413d517aca36f13a15."
- 2026-06-02T21:22:00Z: "verify-hal-driver.sh HAL smoke opened /apm44_bridge_ring; helper_build_id and driver_build_id both 0.1.0+2deaf9cd1f98-dirty; capacity_frames=4096."
- 2026-06-02T21:23:15Z: "scripts/ci.sh passed: CMake build, 11 native tests, Swift app build, and 11 Swift unit tests."
- 2026-06-02T21:26:00Z: "After running CI post-install, /apm44_bridge_ring disappeared because shm unit tests used the production shm name and called shm_unlink; tests now use per-process short shm names."
- 2026-06-02T21:27:00Z: "Focused shm tests passed after install and apm44-bridge --shm-status still returned ok, proving tests no longer clobber the production ring."
- 2026-06-02T21:29:03Z: "Rebuilt Release app, embedded rebuilt helper, replaced /Applications/APM44 Bridge.app, and verified embedded helper hash matches build/BridgeDaemon/apm44-bridge."

## Eliminated

- hypothesis: "Cubase had not started playback."
  result: "Unlikely: an explicit IOProc probe reportedly started the CoreAudio device successfully and the ring still did not exist."

## Resolution

- root_cause: "Two issues combined: the installed HAL driver could drift from the helper/build with silent shm create/open failures, and local shm tests used /apm44_bridge_ring directly, so running tests on a machine with an installed driver could unlink the production ring."
- fix: "Added shm ABI/build-ID metadata, open/create errno diagnostics, fast-fail daemon behavior, driver unified-log errors, helper --shm-status, apm44-hal-smoke, stricter install/verify hash checks, clearer app failure messaging, isolated test shm names, and docs."
- verification: "Installed matching driver via admin installer, reloaded coreaudiod, replaced /Applications app with matching embedded helper, verify-hal-driver.sh passed with HAL smoke, apm44-bridge --shm-status returned ok, scripts/ci.sh passed, and focused shm tests no longer delete the production ring after install."
- files_changed: "Shared ring layout/MmapShmRing, driver shm handler, daemon CLI/engine/feed, HAL smoke tool, CMake, menu app process messaging, install/verify/release scripts, docs."
