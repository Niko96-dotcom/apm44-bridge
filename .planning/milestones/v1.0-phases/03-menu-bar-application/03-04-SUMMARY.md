---
phase: 03-menu-bar-application
plan: 04
subsystem: ui
tags: [devices, picker, list-devices]
requires: []
provides:
  - DeviceCatalog from --list-devices TSV
  - Persisted output UID
affects: [03-06]
tech-stack:
  added: []
  patterns: [AirPods/USB sort priority]
key-files:
  created: [App/APM44Bridge/DeviceCatalog.swift, tests/test_device_catalog.swift]
  modified: [App/APM44Bridge/BridgeSettings.swift, App/APM44Bridge/MenuContentView.swift]
requirements-completed: [APP-01, APP-04]
duration: 10min
completed: 2026-06-01
---

# Phase 3 Plan 04: Device Picker Summary

**Output picker lists `apm44-bridge --list-devices` outputs and passes `--output-device` on start.**

## Task Commits

1. **Tasks 1–2** - `496f1b0` (feat)

## Self-Check: PASSED
