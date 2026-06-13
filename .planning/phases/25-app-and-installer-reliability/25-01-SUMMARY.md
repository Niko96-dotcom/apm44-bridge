---
phase: 25-app-and-installer-reliability
plan: 01
subsystem: menu-bar-app
tags: [swift, device-catalog, metrics, lifecycle]
provides:
  - Non-blocking DeviceCatalog helper stderr behavior
  - Shared BridgeProcessManager metrics reset helper
  - Swift unit coverage for refresh and metrics lifecycle contracts
key-files:
  created:
    - .planning/phases/25-app-and-installer-reliability/25-01-SUMMARY.md
  modified:
    - App/APM44Bridge/DeviceCatalog.swift
    - App/APM44Bridge/BridgeProcessManager.swift
    - tests/test_device_catalog.swift
    - tests/test_bridge_process_manager.swift
requirements-completed: [APP-06, APP-07]
completed: 2026-06-13
---

# Phase 25 Plan 01 Summary: App Refresh and Metrics Reset

## Accomplishments

- Changed `DeviceCatalog.refresh` to send helper stderr to `FileHandle.nullDevice` instead of an unread pipe.
- Added a Swift regression guard for the stderr behavior.
- Added `resetMetricsState()` to clear `latestMetrics`, `lastMetricsAt`, and `metricsStale` together.
- Called the reset helper from bridge start and idle transition.
- Added Swift tests for start reset and idle-transition reset.

## Verification

```bash
xcodebuild -project App/APM44Bridge.xcodeproj -scheme APM44Bridge -destination 'platform=macOS' -derivedDataPath build/app test -only-testing:APM44BridgeTests CODE_SIGNING_ALLOWED=NO
```

Result: passed, 46 tests.
