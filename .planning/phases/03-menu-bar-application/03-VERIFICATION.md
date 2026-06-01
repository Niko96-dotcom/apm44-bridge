# Phase 3 verification: Menu Bar Application

**Date:** 2026-06-01  
**Overall status:** `passed` (automated); `human_needed` (hardware UAT per `docs/menu-bar-qa.md`)

## Automated checks

| Check | Status | Notes |
|-------|--------|-------|
| `bash scripts/verify-app-build.sh` | passed | XcodeGen + `xcodebuild` Debug |
| `bash scripts/verify-menu-bar.sh` | passed | App build, metrics ctest, Swift tests, invariants |
| `ctest -R test_bridge_metrics_json` | passed | JSON schema + `estimated_rt_ms` |
| `APM44BridgeTests` (8 tests) | passed | Parser, device catalog, latency presets |
| `apm44-bridge --help` | passed | Lists `--metrics-json` |
| `apm44-bridge --list-devices` | passed | Pre-existing; used by `DeviceCatalog` |
| Prohibited latency copy scan | passed | No "zero latency" in `App/` |

## Hardware-dependent checks

| Check | Status | Notes |
|-------|--------|-------|
| DAW → BlackHole @ 44.1 → bridge → AirPods monitoring | human_needed | See `docs/menu-bar-qa.md` |
| Hotplug disconnect/reconnect auto-restart | human_needed | APP-04 |
| Latency preset listening (~30 s each) | human_needed | APP-02 |
| Live meters under load | human_needed | APP-05 |

## Requirements traceability

| ID | Status | Evidence |
|----|--------|----------|
| APP-01 | passed (automated) / human_needed (audio) | Menu shell, picker, icon states; audio path needs hardware |
| APP-02 | passed (automated) | `LatencyPreset` 8/15/30 ms + UI |
| APP-03 | passed (automated) | `SrcQuality` picker + override |
| APP-04 | passed (code) / human_needed (hotplug) | `HotplugMonitor` + `handleHotplug` |
| APP-05 | passed (automated UI) / human_needed (meters) | Parser + `ProgressView` fill |
| QA-03 | passed (automated) | `~N ms monitoring latency`; `estimated_rt_ms` never forced to 0 in label |

## UI-SPEC alignment

Implementation follows `03-UI-SPEC.md` (320 pt popover, sections, copywriting contract, preset table). Checker sign-off pillars not re-run by gsd-ui-checker this session.

## Commit references

| Plan | Commit |
|------|--------|
| 03-02 | `e4f56a3` |
| 03-01–03-06 (app) | `496f1b0` |
| 03-07 | `5e16757` |

## Gaps / deferred

- Hardware UAT checkpoint auto-approved for execution (`--no-transition`); producer must run `docs/menu-bar-qa.md` before daily-driver use.
- `APM44Bridge.xcodeproj` generated via `xcodegen` (gitignored); CI/dev runs `scripts/verify-app-build.sh` which regenerates when missing.
- XPC daemon control deferred to later phase (subprocess MVP per CONTEXT).
