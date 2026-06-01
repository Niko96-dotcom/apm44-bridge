---
phase: 06-hal-signing-load-verification
title: HAL Signing & Load Verification
---

# Phase 6 Context

## Goal
Developer ID sign all binaries; notarize workflow; verify HAL loads on sign-off Mac.

## Decisions (autonomous)
- Use `Developer ID Application: Nikolay Mohr (4H5447ZWS3)` as default SIGN_ID
- Notary profile `AC_NOTARY` on sign-off Mac; CI uses workflow_dispatch stub without secrets
- Local scripts are primary path; GitHub Actions optional when secrets exist

## Constraints
- macOS 15+ rejects ad-hoc HAL — production requires notarized driver
- Shm 0666 fix already in tree (Shared/src/MmapShmRing.cpp)
