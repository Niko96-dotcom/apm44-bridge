---
phase: 03-menu-bar-application
plan: 03
subsystem: ui
tags: [metrics, parser, swiftui]
requires:
  - phase: 03-menu-bar-application
    provides: plan 03-02 JSON contract
provides:
  - MetricsParser and live meters in menu
affects: []
tech-stack:
  added: []
  patterns: [stdout line parser, glitch flash on xrun delta]
key-files:
  created: [App/APM44Bridge/MetricsParser.swift, App/APM44Bridge/BridgeMetricsSnapshot.swift, tests/test_metrics_parser.swift]
  modified: [App/APM44Bridge/BridgeProcessManager.swift, App/APM44Bridge/MenuContentView.swift]
requirements-completed: [APP-01, APP-05, QA-03]
duration: 15min
completed: 2026-06-01
---

# Phase 3 Plan 03: Live Meters Summary

**Menu parses daemon JSON lines and shows buffer fill, glitch indicator, and `~N ms monitoring latency` copy.**

## Task Commits

1. **Tasks 1–2** - `496f1b0` (feat)

## Self-Check: PASSED
