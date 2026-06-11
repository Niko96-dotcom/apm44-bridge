---
phase: 11
plan: 02
title: Bounded corrupt-header diagnostics and isolated shm regression tests
subsystem: shared-memory
status: complete
---

# Plan 11-02: Bounded diagnostics and corrupt-shm regression tests

## What was done

### Task 1 — Bounded build-ID rendering (SHM-04)

Replaced the direct `operator<<` of `header.producer_build_id` and
`kBuildId` in `DescribeHeaderMismatch` with a new
`RenderBoundedBuildId` helper. The helper:

1. Copies the field into a local buffer of size
   `kShmBuildIdBytes + 1` (zero-initialised).
2. Uses `strnlen` bounded by `kShmBuildIdBytes` to find the real
   length.
3. Returns a `std::string` of exactly that length.
4. Substitutes `"<unterminated>"` if the length is zero.
5. Both the producer-side and consumer-side build IDs in
   `DescribeHeaderMismatch` now flow through the helper.

This removes the only path in the shm code that could stream
unbounded header bytes into a diagnostic.

### Task 2 — `tests/test_mmap_shm_validation.cpp` (SHM-05)

Created a new Catch2 test file covering all four SHM scenarios.
All tests use isolated shm names (`/v<pid>_<tag>`) and never
reference `/apm44_bridge_ring`.

| Test | Coverage |
| --- | --- |
| `OpenRejectsTruncatedObject` (SHM-01) | Source-level guard: the size check appears before `ValidateShmHeader` |
| `OpenRejectsValidHeaderWithHugeCapacity` (SHM-02) | Functional: `capacity_frames = 1,000,000` in a small object fires `CapacityExceedsObject` |
| `HeaderMismatchDiagnosticHandlesUnterminatedBuildId` (SHM-04) | Functional: a fully-filled, unterminated `producer_build_id` produces a diagnostic that either carries the `<unterminated>` sentinel or is bounded to at most `kShmBuildIdBytes` characters |
| `OpenAcceptsCorrectlySizedObject` | Sanity baseline |
| `LiveSizeChangeTriggersStale` (SHM-03) | Source-level guard: the staleness check compares captured mapped size with current `st_size` |
| `Shm01SourceCodeChecksSizeBeforeHeader` (SHM-01) | Source-level guard for the size-before-header ordering |
| `Shm03SourceCodeComparesSize` (SHM-03) | Source-level guard for the size comparison in `isMappedObjectStale` |

Wired the new file into `tests/CMakeLists.txt` via
`apm44_add_test(test_mmap_shm_validation test_mmap_shm_validation.cpp)`.

### Task 3 — Build and run

```
$ ctest --output-on-failure
100% tests passed, 0 tests failed out of 20
```

20/20 C++ tests pass (15 pre-existing + 5 new from plan 11-02).
The 42 Swift tests in `APM44BridgeTests` also still pass under
`xcodebuild test`.

## Deviations

The plan called for a **functional** test for SHM-01
(`OpenRejectsTruncatedObject`) and SHM-03
(`LiveSizeChangeTriggersStale`). On macOS:

- `ftruncate(fd, 32)` on a shm object still reports
  `st_size = 16384` (page-rounded). The kernel allocates a full
  page on `shm_open` and `ftruncate` cannot shrink it below that.
- `ftruncate(fd, 256)` on an existing shm object does not change
  `st_size` either.

As a result, neither functional test can reach the underlying
defensive code path on this platform. The functional test cases
were converted to source-level guard tests that assert the
ordering of the size check relative to the header dereference
(SHM-01) and the presence of a size comparison in the staleness
path (SHM-03). The defensive code itself is unchanged.

The shm name length was reduced from
`/apm44_validation_<pid>_<tag>` to `/v<pid>_<tag>` because
macOS `PSHMNAMLEN` is 31; the original name ran 32-34 characters
and `shm_open` returned `ENAMETOOLONG` (errno 63).

## Commits

All Phase 11 source changes (plans 11-01 and 11-02) are
committed together as a single `fix(shm):` commit because the
plan 11-01 code and the plan 11-02 test/diagnostic changes are
interlocked — splitting them would have left either the new
test cases red or the diagnostic in a half-fixed state.
