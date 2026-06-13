---
phase: 24-converter-and-metrics-realtime-safety
plan: 01
subsystem: bridge-daemon-src
tags: [converter, cli, cmake, catch2]
provides:
  - Removed public legacy converter CLI/runtime path
  - Removed AudioConverterSrc build and test inputs
  - Source guard preventing converter path reintroduction
key-files:
  created:
    - .planning/phases/24-converter-and-metrics-realtime-safety/24-01-SUMMARY.md
  modified:
    - BridgeDaemon/src/CliOptions.cpp
    - BridgeDaemon/src/CliOptions.h
    - BridgeDaemon/src/engine/BridgeEngine.cpp
    - BridgeDaemon/src/engine/BridgeEngine.h
    - BridgeDaemon/CMakeLists.txt
    - tests/CMakeLists.txt
    - tests/test_bridge_metrics_json.cpp
    - docs/soak-test.md
  deleted:
    - BridgeDaemon/src/engine/AudioConverterSrc.cpp
    - BridgeDaemon/src/engine/AudioConverterSrc.h
    - tests/test_audio_converter_src.cpp
requirements-completed: [CONV-01]
completed: 2026-06-13
---

# Phase 24 Plan 01 Summary: Legacy Converter Removal

## Accomplishments

- Removed `--legacy-converter` from help text, parsing, CLI options, and engine option translation.
- Removed the legacy converter branch and member state from `BridgeEngine`; runtime now always uses `LibSamplerateSrc`.
- Removed `AudioConverterSrc.cpp` from the bridge daemon target and removed the obsolete converter test target.
- Deleted the obsolete `AudioConverterSrc` source/header and `test_audio_converter_src.cpp`.
- Removed the debug converter snippet from `docs/soak-test.md`.
- Added `LegacyConverterPathRemovedFromPublicRuntime` source guard coverage.

## Verification

```bash
rg -n -- '--legacy-converter|legacyConverter|useLegacyConverter|AudioConverterSrc' BridgeDaemon docs tests README.md scripts .github || true
cmake -S . -B build
cmake --build build --target apm44-bridge test_bridge_metrics_json
ctest --test-dir build -R test_bridge_metrics_json --output-on-failure
```

Result: converter grep returned no matches; build and targeted test passed.
