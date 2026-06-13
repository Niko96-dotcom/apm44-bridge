# Phase 24: Converter and Metrics Realtime Safety - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 24 removes the public legacy AudioToolbox converter debug path and makes realtime metrics floating-field publication use lock-free integer atomics rather than `std::atomic<double>`.

</domain>

<decisions>
## Implementation Decisions

### Legacy Converter Removal
- Remove `--legacy-converter` from CLI help, parsing, bridge options, startup logging, docs, CMake inputs, and tests.
- Keep the supported SRC path on `LibSamplerateSrc`; do not retain a user-selectable fallback.
- Remove the obsolete `AudioConverterSrc` implementation and its test target from the build.
- Add or keep source guards so the removed flag and build target cannot silently return.

### Metrics Atomic Representation
- Replace `std::atomic<double>` metrics payload fields with `std::atomic<uint64_t>` bit-packed double storage.
- Preserve the existing `PublishMetrics` and `ReadMetrics` API.
- Use `std::bit_cast` for exact double round-trips without allocation, mutexes, or blocking work.
- Add regression coverage proving packed floating fields round-trip and `std::atomic<double>` is absent from the realtime publisher.

### the agent's Discretion
The agent may choose the smallest source-guard shape that proves the converter path is gone, as long as it runs in the native test suite and does not depend on generated build files.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BridgeDaemon/src/CliOptions.*` owns public flag parsing and engine option translation.
- `BridgeDaemon/src/engine/BridgeEngine.*` currently switches between `LibSamplerateSrc` and `AudioConverterSrc`.
- `BridgeDaemon/CMakeLists.txt` and `tests/CMakeLists.txt` are the public build/test surfaces for the legacy converter path.
- `tests/test_bridge_metrics_json.cpp` already hosts metrics publisher and source-shape guards.

### Established Patterns
- Runtime safety invariants are backed by targeted Catch2 tests plus source scans for forbidden patterns.
- Public release minimization is preferred over preserving debug-only alternate paths.
- Metrics publication must stay lock-free and free of mutexes, allocations, and logging on the realtime path.

### Integration Points
- `BridgeEngine::prepare`, `converterRatio`, and `onOutput` currently branch on `useLegacyConverter_`.
- CLI `ToEngineOptions` currently maps `legacyConverter` into `BridgeEngineOptions`.
- `docs/soak-test.md` contains the only public documentation reference to the legacy flag.

</code_context>

<specifics>
## Specific Ideas

Delete the converter source/test files, remove CMake references, remove CLI and engine option fields, and bit-pack floating metrics fields through `std::atomic<uint64_t>`.

</specifics>

<deferred>
## Deferred Ideas

None - retaining or repairing `--legacy-converter` is explicitly out of scope.

</deferred>
