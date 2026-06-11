# Stack Research: v0.3 Realtime Audio Hardening

**Domain:** macOS Core Audio HAL bridge hardening
**Researched:** 2026-06-12
**Confidence:** HIGH for local stack, MEDIUM for implementation ordering

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| C++ | C++20 via CMake | Daemon, shared memory, ring buffers, metrics | Existing daemon/shared code is C++; C++20 atomics and standard library are enough for race-free snapshots without new dependencies. |
| Swift | Apple Swift 6.3.2 | Menu bar app process lifecycle | Existing app uses Swift concurrency and `Process`; the stop-timeout fix should stay in this layer. |
| Core Audio | macOS 14+ deployment target | Input/output IOProcs and HAL virtual device | Existing product contract depends on Core Audio callbacks and HAL driver behavior. |
| POSIX shm | macOS POSIX shared memory | HAL driver to daemon audio transport | Existing IPC path is shm-based; v0.3 should harden validation rather than replace transport. |
| Catch2 | v3.5.4 | C++ regression tests | Already integrated by `tests/CMakeLists.txt`; ideal for ring, callback, metrics, and shm edge cases. |
| XCTest | Xcode macOS scheme | Swift process manager tests | Existing tests cover lifecycle; add stop-timeout/concurrent-waiter coverage here. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| libsamplerate | vendored | SRC processing | Keep unchanged; v0.3 should avoid converter churn unless callback chunking exposes a direct issue. |
| libASPL | vendored | HAL driver scaffolding | Keep existing Float32 HAL contract; this milestone is IPC/callback hardening, not stream-format redesign. |
| Darwin/POSIX | system | `kill`, `shm_open`, `fstat`, `mmap`, `munmap` | Required for process escalation and shm validation. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `scripts/ci.sh` | Full non-hardware verification | Runs secret scan, CMake build/tests, Swift app build, Swift unit tests. |
| `ctest --test-dir build --output-on-failure` | Native regression loop | Use for ring/callback/metrics/shm tests. |
| `xcodebuild ... -only-testing:APM44BridgeTests` | Swift lifecycle regression loop | Use for stop escalation and concurrent waiter tests. |
| `scripts/verify-installed-sync.sh` | Installed helper/repo/live shm build-ID proof | Exists but is not CI-gated yet; v0.3 should wire at least dry-run coverage into CI. |
| `scripts/verify-hal-driver.sh` | Live driver verification | Still required for final live proof on operator hardware. |

## Installation

No stack additions are recommended.

```bash
bash scripts/ci.sh
ctest --test-dir build --output-on-failure
xcodebuild -project App/APM44Bridge.xcodeproj \
  -scheme APM44Bridge \
  -destination 'platform=macOS' \
  test -only-testing:APM44BridgeTests \
  CODE_SIGNING_ALLOWED=NO
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Independent atomic metric fields | Seqlock over plain struct payload | Do not use the current seqlock pattern unless the payload buffer is made race-free. Plain non-atomic payload reads/writes are the issue. |
| Keep SPSC ring ownership strict | Producer-side drop-oldest by calling `pop()` | Avoid; it violates the documented ring contract when output is also the consumer. |
| Chunk/zero whole output callback | Keep clamping to 1024 frames | Avoid; a larger Core Audio buffer can leave the tail stale or untouched. |
| Explicit waiter bookkeeping in Swift | `withThrowingTaskGroup` plus one stored continuation | Avoid; cancellation does not resume a checked continuation, and one continuation can be overwritten. |
| Validate mapped size before trusting shm capacity | Header-only validation | Avoid; a small shm object can claim a large capacity. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Mutexes or blocking repair inside IOProcs | Real-time callback path must not block or allocate. | Preallocated scratch, bounded loops, non-RT control-path recovery. |
| Producer-side consumer operations on `PlanarRingBuffer` | Breaks single-consumer ownership of `readIndex_`. | Drop-newest on input overflow or move oldest-drop policy to output thread. |
| Raw C-string formatting for shm build IDs | Corrupt headers may not contain a NUL terminator. | Bounded string conversion over the 64-byte array. |
| Tests using `/apm44_bridge_ring` | Can destroy the production live ring. | Isolated short shm names per test process. |
| Replacing the audio stack to fix local races | Adds risk and scope without addressing root causes. | Keep stack; harden ownership, validation, and verification. |

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| CMake 4.3.3 | C++20 project | Local `cmake --version` reports 4.3.3; `CMakeLists.txt` requires CMake 3.28 minimum. |
| Apple clang 21.0.0 | C++20 daemon/shared tests | Local `clang++ --version` reports Apple clang 21.0.0. |
| Apple Swift 6.3.2 | macOS app tests | Local `swift --version` reports Swift 6.3.2. |
| Catch2 v3.5.4 | CMake native tests | Fetched by `tests/CMakeLists.txt`. |

## Sources

- Local source audit: `BridgeInputOverrun.h`, `PlanarRingBuffer.cpp`, `IoProcHandlers.cpp`, `BridgeEngine.cpp`, `MmapShmRing.cpp`, `ShmObjectIdentity.h`, `BridgeProcessManager.swift`.
- Local verification scripts: `scripts/ci.sh`, `scripts/verify-installed-sync.sh`, `scripts/verify-hal-driver.sh`.
- Local toolchain commands: `swift --version`, `clang++ --version`, `cmake --version`.

---
*Stack research for: v0.3 Realtime Audio Hardening*
*Researched: 2026-06-12*
