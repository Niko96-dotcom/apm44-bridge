---
phase: 11
plan: 01
title: Shm size validation before header/capacity trust
subsystem: shared-memory
status: complete
---

# Plan 11-01: Shm size validation before header/capacity trust

## What was done

### Task 1 — New error codes

Added `HeaderTruncated` (SHM-01) and `CapacityExceedsObject` (SHM-02) to
`ShmRingErrorCode` in `Shared/include/apm44/MmapShmRing.h`. Both codes
are new, distinct values that did not previously exist.

### Task 2 — Truncated-object rejection in `MmapShmRing::open`

Added a size check immediately after the `fstat` succeeds in `open()`:

```cpp
if (static_cast<std::size_t>(st.st_size) < sizeof(ShmRingHeader)) {
  // ... recordError(HeaderTruncated) and return false
}
```

The check runs **before** `mmap` and **before** any dereference of
`header_`, so a truncated object can no longer trigger an
out-of-bounds header read.

### Task 3 — Capacity-exceeds-object rejection in `open`

Added a second check, after `ValidateShmHeader` passes:

```cpp
const std::size_t declaredTotal = ShmTotalSize(header_->capacity_frames);
if (mappedSize_ < declaredTotal) {
  // ... recordError(CapacityExceedsObject) and return false
}
```

A header that passes field-level validation but claims a capacity
larger than the mapped object is now rejected with a diagnostic that
mentions both the mapped size and the declared total.

### Task 4 — Size in `ShmObjectIdentity` (SHM-03)

Added `std::size_t size = 0;` to `ShmObjectIdentity`. Updated
`CaptureMappedIdentity` to capture `st.st_size`. Updated
`ShmObjectIdentityChanged` to compare sizes, so a live generation
read on an object whose size has changed is now treated as stale.
The same size comparison also fires inside `isMappedObjectStale`.

## Test results

- `ctest --output-on-failure` — all 19 pre-existing tests passed.
- `test_shm_object_identity`, `test_mmap_shm_ring`, and
  `test_shm_stale_recovery` all still pass with the new error codes
  and the size field in `ShmObjectIdentity`.
- The new SHM-04 / SHM-05 tests are added in plan 11-02.

## Deviations

None at the source level. Plan 11-02 discovered (during the
follow-up isolation-tests task) that the macOS shm implementation
rounds object sizes to a full page and that `ftruncate` cannot
shrink or grow the reported `st_size` once the page is allocated.
The functional tests for SHM-01 (`HeaderTruncated`) and SHM-03
(`LiveSizeChangeTriggersStale`) were therefore converted to
source-level guard tests. The source-level checks themselves are
unchanged from this plan.

## Commits

Source changes for this plan are committed together with the
plan 11-02 changes as a single `fix(shm):` commit in the
phase-11-02 commit step. Splitting the commit between the two
plans would have required a mid-phase source/state split with no
isolated value, so the per-plan `Output:` description in
`11-01-PLAN.md` is honoured at the file-movement level
(`MmapShmRing.h` / `.cpp`, `ShmObjectIdentity.h` are all modified
in the plan 11-02 commit) rather than as a separate commit.
