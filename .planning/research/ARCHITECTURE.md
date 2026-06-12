# Architecture Research

**Domain:** macOS audio bridge public-release hardening
**Researched:** 2026-06-12
**Confidence:** HIGH

## Standard Architecture

### System Overview

```text
+-------------------------------------------------------------+
|                 Release Validation Surface                  |
|  scripts/ci.sh  release-all.sh  sign-notarize.yml  docs     |
+-------------------------------------------------------------+
|                  Public Artifact Pipeline                   |
|  app build -> sign app/driver -> staple inner artifacts      |
|  -> build/notarize/staple DMG or PKG -> spctl validation     |
+-------------------------------------------------------------+
|                  Runtime Correctness Layer                  |
|  MetricsPublisher  BridgeMetrics JSON  IOProc callbacks     |
|  BridgeEngine start/stop error paths                        |
+-------------------------------------------------------------+
|                  HAL / Shared-Memory Boundary               |
|  APM44Bridge.driver -> /apm44_bridge_ring -> daemon          |
|  local IPC threat model, shm mode, build-ID sync             |
+-------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `MetricsPublisher` | Transfer metrics from realtime/control paths to CLI/UI readers without data races | Atomic field representation or proven triple-buffer ownership. |
| `BridgeMetrics::ToJsonLine` | Serialize daemon metrics safely for CLI/app consumption | Check `snprintf` return and never construct strings past buffer length. |
| `IoProcHandlers` | Convert Core Audio buffers into engine input/output safely | Clamp by every channel buffer; silence all output tails. |
| `BridgeEngine::start/stop` | Create/start/cleanup IOProcs symmetrically | Cleanup only resources created for the active mode. |
| Release shell scripts | Build/sign/notarize/staple artifacts | Fail closed, print logs, require explicit override for local-only unsigned output. |
| GitHub workflows | CI/release automation | No masked build failures; pin or justify critical actions. |
| Docs | Public release trust model | Describe install UX, shm local IPC assumptions, and validation commands. |

## Recommended Project Structure

Keep the existing structure. v0.4 should patch in place:

```text
BridgeDaemon/src/engine/
+-- MetricsPublisher.h       # atomic metrics publication contract
+-- BridgeMetrics.cpp        # JSON truncation guard
+-- BridgeEngine.cpp         # virtual-device output-start failure cleanup
+-- IoProcHandlers.cpp       # non-interleaved input min-frame sizing, dead helper cleanup
+-- BridgeInputOverrun.h     # rename or compatibility wrapper for drop-new policy

tests/
+-- test_bridge_metrics.cpp  # JSON truncation regression
+-- test_metrics_publisher*  # race-free/TSan/source guard coverage
+-- test_io_proc_callbacks.cpp
+-- release script tests     # mocked xcrun/notarytool where repo convention supports it

scripts/
+-- notarize-release-dmg.sh
+-- notarize-release-pkg.sh
+-- release-all.sh
+-- ci.sh

.github/workflows/
+-- sign-notarize.yml
+-- release.yml
+-- ci.yml
+-- codeql.yml

docs/
+-- release.md
+-- hal-driver.md
+-- install.md
```

### Structure Rationale

- **Patch existing release scripts:** avoids competing release paths.
- **Keep metrics fix behind `MetricsPublisher`:** reduces blast radius and keeps `BridgeEngine` behavior stable.
- **Use docs for security posture:** world-writable local shm may be acceptable for v0.4 only if it is not invisible.
- **Keep public UX decisions near release docs/scripts:** roadmapping can decide whether PKG becomes primary without mixing that into realtime callback work.

## Architectural Patterns

### Pattern 1: Atomic Metrics Record

**What:** Store counters as `std::atomic<uint64_t>` and doubles as `std::atomic<uint64_t>` bit patterns. Readers reconstruct a `MetricsSnapshot` value from atomics.

**When to use:** Single writer/multiple readers where values are telemetry and exact cross-field simultaneity is less important than race-free publication.

**Trade-offs:** Simple and RT-friendly; may need a generation counter if readers require all fields from one publication.

### Pattern 2: Triple Buffer With Ownership

**What:** Writer publishes into a buffer that no reader can concurrently copy; readers acquire a stable buffer index.

**When to use:** If cross-field snapshot consistency is mandatory and atomics for each field are too cumbersome.

**Trade-offs:** More complex lifetime rules; still RT-friendly when preallocated.

### Pattern 3: Fail-Closed Release Command

**What:** Release scripts treat any unexpected return code or non-accepted notary status as failure. Local development escape hatches are explicit and named.

**When to use:** Any command that can produce public artifacts.

**Trade-offs:** More annoying for maintainers; much safer for public publishing.

### Pattern 4: Mock External CLIs in Script Tests

**What:** Put a fake `xcrun` earlier on PATH and feed controlled `notarytool` output/exit codes.

**When to use:** Release-script regression tests that should run without Apple credentials.

**Trade-offs:** Does not replace live notarization, but catches parser and failure-mode bugs cheaply.

## Data Flow

### Metrics Flow

```text
Audio/control path
    -> MetricsPublisher atomic publish
    -> BridgeEngine readMetricsSnapshot()
    -> BridgeMetrics::ToJsonLine()
    -> CLI stdout / app parser
```

### Release Flow

```text
secret scan
    -> app/native build
    -> verify-app-build
    -> sign app + driver
    -> staple app + driver
    -> build final DMG or PKG
    -> notarytool submit --wait
    -> require status: Accepted
    -> stapler validate
    -> spctl/pkgutil assessment
```

### Local IPC Trust Flow

```text
coreaudiod HAL driver
    -> shm object /apm44_bridge_ring mode 0666
    -> user daemon maps ring
    -> docs describe local read/write/DoS assumptions
    -> future hardening tracks per-user/group/XPC alternatives
```

## Scaling Considerations

This is a local audio utility, not a server. The important scale is operational and temporal:

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single maintainer local build | Scripts may allow explicit unnotarized override. |
| Public GitHub release | Scripts must fail closed and validation must prove exact artifacts. |
| Multiple maintainers | SHA-pinned actions and documented certificate/keychain setup become more important. |
| Broader DAW/device matrix | Add compatibility milestone after release blockers are closed. |

## Anti-Patterns

### Anti-Pattern 1: Telemetry Is "Only Metrics"

**What people do:** Accept data races because metrics are not audio payload.
**Why it's wrong:** Undefined behavior can miscompile, fail under TSan, or create unstable release behavior.
**Do this instead:** Make the publication mechanism standards-compliant and test it under TSan where possible.

### Anti-Pattern 2: Notarization Best-Effort in a Release Command

**What people do:** Continue when credentials are missing or output is not exactly rejected.
**Why it's wrong:** Produces artifacts that look releasable but may fail Gatekeeper.
**Do this instead:** Hard fail unless an explicit local-only override is present.

### Anti-Pattern 3: Security by Omission

**What people do:** Leave `0666` shm mode undocumented because changing it is larger work.
**Why it's wrong:** Users and contributors infer a stronger boundary than exists.
**Do this instead:** Document the threat model now and track stronger ownership as future work.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Apple notary service | `xcrun notarytool submit --wait`, then parse accepted status | Check return code and accepted status; fetch log when id is available. |
| Gatekeeper | `spctl`, `stapler validate`, `codesign --verify` | Validate the final public container and inner artifacts. |
| GitHub Actions | workflow dispatch and CI jobs | Release/signing workflows should not mask failures and should pin critical actions or document exceptions. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Realtime/control -> metrics readers | `MetricsPublisher` | Must be race-free and RT-safe. |
| Core Audio -> engine input | `InputIoProc` channel pointers | Non-interleaved frame count must use the minimum available channel length. |
| Engine start error -> cleanup | `BridgeEngine::start()` | Virtual-device mode should not stop a null/nonexistent input IOProc. |
| Release scripts -> docs | command sequence | Docs must match actual strict behavior and artifact order. |

## Sources

- https://clang.llvm.org/docs/ThreadSanitizer.html
- https://developer.apple.com/developer-id/
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
- https://docs.github.com/en/actions/reference/security/secure-use
- Repo source scan, 2026-06-12.

---
*Architecture research for: APM44 Bridge v0.4 Public Release Blocker Closure*
*Researched: 2026-06-12*
