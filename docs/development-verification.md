# Local verification and performance

Run these commands from the repository root on macOS with full Xcode selected
(`xcode-select -p`), CMake 3.28+, and XcodeGen. No Apple signing credentials or
HAL installation are needed. Initial setup fetches the pinned libASPL and
libsamplerate submodules, Catch2 v3.5.4, and Sparkle 2.9.4 from their public
repositories. Subsequent builds use their local caches.

## Build and test

```bash
bash scripts/ci.sh
```

This exercises native builds/tests, shell regressions, the universal Swift
app, XCTest, ad-hoc signing, embedded helper, version identity, and architecture
checks. It does not install anything. The final sync dry-run compares the
**local build's** app/helper/driver, not the driver currently loaded by Core Audio.
`APM44_SKIP_APP=1 bash scripts/ci.sh` deliberately limits coverage to native
and shell checks. Missing XcodeGen otherwise fails instead of silently skipping
the app and reporting success.

On the development Mac with **Xcode 26.6 / macOS 26.5.2**, the unmodified
build repeatedly stalled at `ExecuteExternalTool ... clang -v -E -dM ...`.
A process sample showed Clang blocked in a diagnostic `write`; the same probe
completed immediately when run directly. This working, opt-in command handles
that toolchain problem:

```bash
APM44_BUFFER_COMPILER_PROBE=1 bash scripts/ci.sh
```

`run-xcodebuild.sh` supplies `xcode-clang-probe.sh` as Xcode's C compiler wrapper.
Only discovery starting with `-v -E -dM` buffers stdout/stderr into temporary
files and closes stdout before emitting stderr. Compiler output and exit
status are preserved; ordinary invocations exec the selected Clang directly.
`bash tests/test_compiler_probe.sh` compares both streams and success/failure
statuses against the real compiler, including a rejected option and `--version`.
No Xcode installation or global preferences are modified. Omit the flag on
unaffected toolchains. The Codex Run action enables it explicitly.

Keep build logs, including the first error, for diagnosis:

```bash
mkdir -p build
APM44_BUFFER_COMPILER_PROBE=1 bash scripts/ci.sh > build/ci-local.log 2>&1
ctest --test-dir build --output-on-failure
bash tests/test_compiler_probe.sh
```

## Fresh worktrees and custom output paths

For a committed revision:

```bash
git worktree add --detach /tmp/apm44-check HEAD
cd /tmp/apm44-check
BUILD_DIR="$PWD/build/check output" APM44_BUFFER_COMPILER_PROBE=1 bash scripts/ci.sh
```

Choose an unused worktree path. Worktrees do not copy uncommitted or untracked
files; transfer those explicitly if checking a working change. The CI command
initializes submodules and generates the ignored Xcode project itself. It
passes the same absolute build directory to DerivedData, helper embedding,
version, architecture, and sync checks, including directories containing spaces.
There is no need to copy another checkout's `build/` or generated `.xcodeproj`.

## Isolated UI workflow

```bash
APM44_BUFFER_COMPILER_PROBE=1 bash scripts/rebuild-and-open-app.sh --isolated
```

This builds the daemon in `build/isolated-native`, builds the app in
`build/isolated-app`, embeds the matching helper, and re-signs the local bundle.
It launches the exact app path and reports its PID and a log-stream command.
The app uses a checkout-specific `com.niko.apm44.local.<hash>` preferences
domain. Automatic updates are disabled, and manual update requests point at
loopback. Only a previous UI process at this checkout's isolated executable
path is stopped. The installed app/helper are left running.

This mode isolates **preferences and the UI process**, not physical audio,
the system HAL driver, or launch-at-login registration. With real audio work
active, exercise output selection, buffering, quality, window reopening, and
Quit while keeping the bridge stopped. Do not click Start, driver maintenance,
or Open at login. Use disposable offline tests for audio verification.

To stop the test instance without rebuilding:

```bash
bash scripts/rebuild-and-open-app.sh --isolated-stop
```

Use the same `APM44_BUILD_CONFIG` for launch and stop if overriding Debug.
The local preferences remain available for another development run. The
older launch modes intentionally retain their existing behavior of stopping
all app/helper processes; use `--isolated` during normal user activity.

## Repeatable ring benchmark

```bash
bash scripts/benchmark-ring.sh > build/ring-current.csv 2> build/ring-build.log
```

Create `build/` first on a new checkout when redirecting there. The script
builds the opt-in `apm44-ring-bench` target in Release for the host architecture
in `build/perf`. Override `APM44_BENCH_BUILD_DIR` or `APM44_BENCH_ARCH` if needed.
Do not reuse a sanitizer directory. It creates a private, PID-named shared
memory object, opens separate producer/consumer mappings, and unlinks it on
exit. The installed driver's ring is never opened.

CSV reports nanoseconds per **stereo push plus pop pair**, the median/min/max
of seven timed batches, after 2,000 warmup transfers. Blocks range from 64 to
4,096 frames; capacities 8,192 and 8,191 cover both regular and irregular
wraparound. Complete channel/sample comparisons occur outside timed regions;
transfer counts are checked inside them. No timing thresholds gate CI.

Save both binaries before rebuilding and alternate their run order on the
same machine while other builds are idle:

```bash
cp build/perf/BridgeDaemon/apm44-ring-bench build/ring-before
# Make the candidate change, then rebuild:
bash scripts/benchmark-ring.sh > build/ring-candidate.csv
cp build/perf/BridgeDaemon/apm44-ring-bench build/ring-after
build/ring-before > build/before-1.csv
build/ring-after  > build/after-1.csv
build/ring-after  > build/after-2.csv
build/ring-before > build/before-2.csv
build/ring-before > build/before-3.csv
build/ring-after  > build/after-3.csv
```

For the original baseline after these changes are present, create a disposable
worktree at `7f83001`, copy just the benchmark source and script into it, and
add its opt-in target (the baseline lacks the measurement tool):

```bash
task_repo="$PWD"
task_baseline="$(mktemp -d /tmp/apm44-baseline.XXXXXX)"
git worktree add --detach "$task_baseline" 7f83001
cp BridgeDaemon/src/tools/apm44_ring_bench_main.cpp "$task_baseline/BridgeDaemon/src/tools/"
cp scripts/benchmark-ring.sh "$task_baseline/scripts/"
cat >> "$task_baseline/BridgeDaemon/CMakeLists.txt" <<'CMAKE'
add_executable(apm44-ring-bench EXCLUDE_FROM_ALL src/tools/apm44_ring_bench_main.cpp)
target_link_libraries(apm44-ring-bench PRIVATE apm44_shared)
CMAKE
(cd "$task_baseline" && bash scripts/benchmark-ring.sh) > "$task_repo/build/baseline.csv"
cp "$task_baseline/build/perf/BridgeDaemon/apm44-ring-bench" build/ring-before
```

## Audio correctness checks

```bash
ctest --test-dir build -R 'mmap_shm|shm_io|virtual_device|io_proc|samplerate|soak' --output-on-failure
build/BridgeDaemon/apm44-soak --duration-sec 60
build/BridgeDaemon/apm44-bridge --list-devices
```

The soak simulates 60 seconds of 44.1-to-48 kHz conversion with clock skew;
it is not 60 seconds of physical playback. Device listing is read-only.
Tests cover routing callbacks, stereo ordering, starvation recovery, stale
shared-memory recovery, ownership/corrupt-header rejection, and queue limits.
The new FIFO model checks partial writes/reads and repeated wraps at capacities
2, 7, 8, 8,191, and 8,192, alternating interleaved and planar reads with guard
samples outside the requested output. It compares exact samples to a separate
queue model.

Address/undefined-behavior sanitizer checks:

```bash
cmake -S . -B build/asan-perf -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DAPM44_SANITIZER=address
cmake --build build/asan-perf --parallel --target \
  test_mmap_shm_ring test_mmap_shm_validation test_shm_io_handler test_virtual_device_feed
ctest --test-dir build/asan-perf \
  -R '^test_(mmap_shm_ring|mmap_shm_validation|shm_io_handler|virtual_device_feed)$' \
  --output-on-failure
```

Use the host architecture on Intel. On Apple Silicon with Rosetta installed,
`arch -x86_64 build/tests/test_mmap_shm_ring` also exercises the Intel slice
from the universal CI build.

## Measurements and verified coverage — 2026-09-05

Apple M5 Pro, macOS 26.5.2, Xcode 26.6 / Clang 21, CMake 4.3.3,
arm64 Release (`-O3 -DNDEBUG`), 8,192-frame ring. Baseline product source was
`7f83001`, with the benchmark added before changing ring code. Values below
are the median of three process-run medians (seven batches per run), using
alternating baseline/candidate order with compilation finished.

| Push + pop layout | Frames | Before ns | After ns | Reduction |
|---|---:|---:|---:|---:|
| Planar output (daemon path) | 64 | 72.25 | 27.96 | 61.3% |
| Planar output | 256 | 282.78 | 64.83 | 77.1% |
| Planar output | 512 | 562.71 | 112.74 | 80.0% |
| Planar output | 1,023 | 1,142.46 | 237.49 | 79.2% |
| Planar output | 4,096 | 4,410.70 | 830.69 | 81.2% |
| Interleaved output | 512 | 590.09 | 129.80 | 78.0% |
| Interleaved output | 4,096 | 4,369.82 | 787.73 | 82.0% |

The change replaces per-frame remainder operations with at most two contiguous
spans. Interleaved spans use `memcpy`; planar output deinterleaves each span.
All ownership/header/index validation, reserved-slot capacity, partial-transfer
behavior, and acquire/release publication remain intact.

These are warm-cache, single-thread transfer measurements through separate
mappings, not cross-process contention, full callback CPU, scheduling tails,
power consumption, listening quality, or end-to-end monitoring latency. The
absolute saving is about 0.45 microseconds at 512 frames and 3.58 microseconds
at 4,096 frames for the planar pair. Background OS/user activity still causes
variation; initial measurements during compilation were excluded from the
table. The unchanged SRC and configured audio latency should not be credited
with these percentage reductions.

Successfully exercised:

- All 19 native suites and 67 Swift tests in the primary checkout and a fresh
  detached worktree, with no build cache/project copied between them. The
  worktree used `build/check output` to exercise spaces and custom paths.
- Universal app/daemon/driver builds, local ad-hoc signatures and helper identity.
- Four affected suites under address/undefined-behavior sanitizers.
- The native Intel ring test under Rosetta.
- Both 60-second offline soaks: zero underruns/overruns, mean fill 17.8293 ms,
  maximum fill 20.3628 ms, final drift -44.7 ppm. This soak does not use the
  optimized shared-memory transfer and is correctness evidence, not a speedup.
- Isolated UI launch/reopen, device enumeration/selection, Balanced buffering
  displaying the 20 ms HAL minimum, SRC quality selection, and isolated stop.
  Runtime logs were inspectable by PID. The installed app and helper retained
  their original PIDs throughout these checks.

Unverified: loading this changed HAL binary into Core Audio, playback/export
through a DAW, USB-C AirPods Max behavior, listening for clicks, and a real
hardware soak. Those require a disposable DAW project, the USB-C headphones,
and a separately authorized driver install/Core Audio restart during an idle
audio session. No release signing, publication, or production installation was
performed.
