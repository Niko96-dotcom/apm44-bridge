---
phase: 03-menu-bar-application
plan: 06
subsystem: ui
tags: [hotplug, coreaudio]
requires:
  - phase: 03-menu-bar-application
    provides: device picker and process manager
provides:
  - HotplugMonitor with 1 s debounce
  - Auto-restart when bridge was running
affects: []
tech-stack:
  added: []
  patterns: [kAudioHardwarePropertyDevices listener]
key-files:
  created: [App/APM44Bridge/HotplugMonitor.swift]
  modified: [App/APM44Bridge/APM44BridgeApp.swift, App/APM44Bridge/BridgeProcessManager.swift]
requirements-completed: [APP-04]
duration: 10min
completed: 2026-06-01
---

# Phase 3 Plan 06: Hotplug Summary

**Core Audio device-list listener debounces 1 s and restarts the bridge if it was running when outputs change.**

## Task Commits

1. **Tasks 1–2** - `496f1b0` (feat)

## Self-Check: PASSED
