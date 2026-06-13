---
phase: 23-hal-runtime-pairing-safety
plan: 02
subsystem: hal-shm-output
tags: [hal, io-stop, shm, catch2]
provides:
  - Stopped-IO early return before stream processing or shm writes
  - Correct HAL shm bounded-ring drop-policy comment
  - Catch2 regression coverage for stopped-IO rejection
key-files:
  created:
    - .planning/phases/23-hal-runtime-pairing-safety/23-02-SUMMARY.md
  modified:
    - Driver/src/ShmIoHandler.cpp
    - tests/test_shm_io_handler.cpp
requirements-completed: [HAL-03, HAL-04]
completed: 2026-06-13
---

# Phase 23 Plan 02 Summary: Stopped IO and Drop Policy

## Accomplishments

- Added an `ioRunning_` guard at the top of `OnProcessMixedOutput`.
- Ensured callbacks after `OnStopIO()` return before stream processing and before shm writes.
- Updated the HAL shm push comment to describe the actual bounded-ring behavior: write available capacity and drop incoming tail frames.
- Added a Catch2 regression proving mixed output after IO stop does not write shm frames.

## Verification

```bash
cmake --build build --target test_shm_io_handler
ctest --test-dir build -R test_shm_io_handler --output-on-failure
```

Result: passed.
