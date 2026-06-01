---
phase: 03-menu-bar-application
plan: 02
subsystem: audio-engine
tags: [json, metrics, cli]
requires:
  - phase: 02-production-src-drift-engine
    provides: BridgeEngine metrics getters
provides:
  - --metrics-json stdout stream
  - BridgeMetrics JSON serializer
affects: [03-03]
tech-stack:
  added: []
  patterns: [500ms main-thread metrics emit, honest estimated_rt_ms]
key-files:
  created: [BridgeDaemon/src/engine/BridgeMetrics.h, BridgeDaemon/src/engine/BridgeMetrics.cpp, tests/test_bridge_metrics_json.cpp]
  modified: [BridgeDaemon/src/CliOptions.cpp, BridgeDaemon/src/main.cpp, BridgeDaemon/src/engine/BridgeEngine.cpp]
key-decisions:
  - "target-fill-ms clamp relaxed to 6–40 ms"
requirements-completed: [APP-05, QA-03]
duration: 20min
completed: 2026-06-01
---

# Phase 3 Plan 02: Metrics JSON Summary

**Daemon emits single-line JSON metrics every 500 ms on stdout when `--metrics-json` is set, with `estimated_rt_ms = fill_ms + SRC group delay`.**

## Task Commits

1. **Task 1 (TDD)** - `e4f56a3` (feat, includes test)
2. **Task 2** - `e4f56a3` (feat)

## Self-Check: PASSED
