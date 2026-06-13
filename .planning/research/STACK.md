# Stack Research

**Domain:** APM44 Bridge public-release safety fixes
**Researched:** 2026-06-13
**Confidence:** HIGH

## Recommended Stack

No new runtime dependencies are needed. v0.6 should use the existing C++20,
Catch2, XCTest, Bash, GitHub Actions, and Apple toolchain surfaces already in
the repo.

| Technology | Purpose | Why Recommended |
|------------|---------|-----------------|
| C++20 | HAL driver and daemon fixes | Existing repo standard; supports atomics and small helper predicates without adding libraries. |
| Catch2 | Native regression coverage | Already covers `ShmIoHandler`, metrics, release-adjacent source guards, shm, and converter behavior. |
| XCTest | Swift app lifecycle and catalog regressions | Existing Swift tests target `BridgeProcessManager`, `DeviceCatalog`, and parser/UI-adjacent state. |
| Bash script tests | Release automation guards | `tests/test_release_scripts.sh` already mocks release tools and can add DMG installer and CI workflow guards. |
| GitHub Actions macOS CI | Public CI gate | `.github/workflows/ci.yml` should run release-script tests in addition to local `scripts/ci.sh`. |
| Apple `ditto`, `chown`, `killall` | DMG command installer | Existing installer already uses sudo for HAL driver install; use the same privilege level for deterministic app copy. |

## Implementation Tools

| Area | Existing File(s) | Tooling Pattern |
|------|------------------|-----------------|
| HAL mono lane pairing | `Driver/src/ShmIoHandler.*`, `tests/test_shm_io_handler.cpp` | Add timestamp metadata and behavioral tests against a real shm ring. |
| HAL IO lifecycle | `Driver/src/ShmIoHandler.cpp` | Add a hot-path guard and a direct stop-then-process regression. |
| Legacy converter | `BridgeDaemon/src/engine/AudioConverterSrc.*`, `BridgeDaemon/src/CliOptions.*`, `tests/test_audio_converter_src.cpp` | Prefer fixing owned input buffer flow if retaining the debug flag; otherwise remove CLI/docs/tests together. |
| Metrics publisher | `BridgeDaemon/src/engine/MetricsPublisher.h`, `tests/test_bridge_metrics_json.cpp` | Store floating metrics as lock-free `uint64_t` bit patterns or add lock-free static assertions. |
| Swift catalog/metrics state | `App/APM44Bridge/*.swift`, `tests/test_*.swift` | Small source changes plus Swift unit tests or targeted source guards. |
| Release scripts | `scripts/build-release-dmg.sh`, `tests/test_release_scripts.sh`, `.github/workflows/ci.yml` | Patch existing scripts and keep tests credential-free. |

## Recommended Choices

### HAL Timestamp Pairing

`PendingLaneBlock` currently stores only `sampleTime`. To make rollover handling
explicit, store both `zeroTimestamp` and `sampleTime`/`timestamp`, then pair only
when:

- the lane sample times match within the existing 0.5-frame tolerance, or
- the absolute logical times `zeroTimestamp + sampleTime` are within a narrow
  rollover tolerance, currently 128 frames based on the observed 68-frame test.

When neither rule matches and no queued exact timestamp match is found, drop the
older logical block rather than pairing arbitrary left/right lanes.

### Legacy Converter

The safest public-release bar is "no unsafe debug flag ships." There are two
acceptable stack choices:

1. Fix `AudioConverterSrc` by pre-interleaving into owned `inputInterleaved_`,
   then have `InputDataProc` set `ioData->mBuffers[0].mData` to owned storage.
2. Remove `--legacy-converter`, `AudioConverterSrc`, its test, and docs mention.

Because the repo already has an isolated `AudioConverterSrc` test and bridge
integration, fixing it is a contained change. Removing it is lower future
maintenance but touches CLI, docs, build files, engine options, and tests.

### Metrics Atomics

Prefer bit-packed `std::atomic<uint64_t>` for `fillMs`, `smoothedRatio`, and
`ppm`. Add:

- `static_assert(std::atomic<uint64_t>::is_always_lock_free, ...)`
- `PackDouble(double) -> uint64_t` via `std::memcpy`
- `UnpackDouble(uint64_t) -> double` via `std::memcpy`

This keeps the realtime publication path free of locks on every supported build
target instead of relying on implementation-specific `std::atomic<double>`.

## What Not To Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| New audio/DSP library | v0.6 is a safety fix milestone, not SRC replacement | Patch the existing HAL and converter seams. |
| Concurrent stderr drain for `DeviceCatalog` unless diagnostics are needed | More code and state for a command whose stderr is not user-visible today | `process.standardError = FileHandle.nullDevice`. |
| A new release framework | Existing shell tests already cover notarization and script behavior | Extend `tests/test_release_scripts.sh`. |
| Broad DAW/hardware scope | Distracts from the nine concrete blockers | Defer soak/matrix work after v0.6. |

## Sources

- `Driver/src/ShmIoHandler.h`
- `Driver/src/ShmIoHandler.cpp`
- `tests/test_shm_io_handler.cpp`
- `BridgeDaemon/src/engine/AudioConverterSrc.cpp`
- `BridgeDaemon/src/engine/MetricsPublisher.h`
- `App/APM44Bridge/DeviceCatalog.swift`
- `App/APM44Bridge/BridgeProcessManager.swift`
- `scripts/build-release-dmg.sh`
- `.github/workflows/ci.yml`
- `scripts/ci.sh`
- `tests/test_release_scripts.sh`

---
*Stack research for: APM44 Bridge v0.6 Public Release Safety Fixes*
*Researched: 2026-06-13*
