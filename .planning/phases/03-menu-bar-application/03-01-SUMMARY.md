---
phase: 03-menu-bar-application
plan: 01
subsystem: ui
tags: [swiftui, menubarextra, subprocess]
requires:
  - phase: 02-production-src-drift-engine
    provides: apm44-bridge CLI
provides:
  - APM44Bridge macOS menu bar app target
  - BridgeProcessManager spawn/stop
affects: [03-03, 03-04, 03-05, 03-06]
tech-stack:
  added: [SwiftUI MenuBarExtra, XcodeGen]
  patterns: [subprocess MVP, BridgeBinaryLocator resolution]
key-files:
  created: [App/APM44Bridge/*.swift, App/project.yml, scripts/verify-app-build.sh, docs/menu-bar-app.md]
  modified: []
key-decisions:
  - "XcodeGen project.yml; xcodeproj generated locally (gitignored)"
requirements-completed: [APP-01]
duration: 25min
completed: 2026-06-01
---

# Phase 3 Plan 01: Menu Bar Shell Summary

**SwiftUI menu bar app spawns `apm44-bridge` with running/stopped/error icon states and Start/Stop control.**

## Task Commits

1. **Tasks 1–2** - `496f1b0` (feat)

## Self-Check: PASSED
