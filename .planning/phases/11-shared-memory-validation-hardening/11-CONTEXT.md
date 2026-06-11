# Phase 11: Shared-Memory Validation Hardening - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous)

<domain>
## Phase Boundary

The daemon rejects malformed HAL shared-memory objects safely before any
ring operation trusts their declared layout. Two sub-domains:

1. **Size validation (SHM-01..SHM-03)** — `MmapShmRing::open()` rejects
   objects smaller than `ShmRingHeader` before reading header fields;
   rejects valid-looking headers whose mapped object is smaller than
   `ShmTotalSize(capacity_frames)`; live driver generation reads check
   object size before mapping or reading a header.
2. **Bounded diagnostics (SHM-04)** — header mismatch diagnostics render
   build IDs with bounded string handling and never assume null
   termination.
3. **Test coverage (SHM-05)** — Catch2 tests cover truncated, header-only,
   huge-capacity, and unterminated build-ID cases with isolated test shm
   names.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices are at Claude's discretion. The
requirements (SHM-01..SHM-05) are authoritative. The selected
approach for each is below.

### Selected Approach

- **SHM-01**: in `MmapShmRing::open()`, after `fstat` returns the
  object size, reject early if `st.st_size < sizeof(ShmRingHeader)`
  with a new `ShmRingErrorCode::HeaderTruncated` (or reuse
  `InvalidHeader` with a clearer message). The header is read only
  after this size check.
- **SHM-02**: after the header is parsed, look up its declared
  `capacity_frames` and reject if the mapped object size is smaller
  than `ShmTotalSize(capacity_frames)`. A new `ShmRingErrorCode::
  CapacityExceedsObject` (or reuse `InvalidHeader`) is appropriate.
- **SHM-03**: in `isMappedObjectStale()` (and in
  `pollStaleRing`/`VirtualDeviceFeed`), if a size mismatch is
  detected on the live generation read, treat the object as stale
  and trigger a remap. The existing size check on `open()` already
  covers remap; the only change needed is to surface "size changed"
  in the staleness check.
- **SHM-04**: change `DescribeHeaderMismatch` to render the build
  IDs with explicit `strnlen` + bounded copy into a `std::string`
  with a fallback `"<unterminated>"` marker if no null terminator
  is found. Same for the `kBuildId` consumer side.
- **SHM-05**: add a `tests/test_mmap_shm_validation.cpp` with
  Catch2 cases that create a test-only shm object, truncate or
  mangle it, and assert the error code / message. Tests use
  PID-based isolated shm names to avoid touching
  `/apm44_bridge_ring`.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MmapShmRing::open()` (Shared/src/MmapShmRing.cpp lines 130-176) —
  the open path; the header dereference and validation happen at
  lines 167-173.
- `MmapShmRing::isMappedObjectStale()` (lines 193-202) — the live
  generation staleness check.
- `DescribeHeaderMismatch()` (lines 46-59) — the diagnostic that
  prints `producer_build_id` directly to a `std::ostringstream`,
  which assumes null termination.
- `ShmRingLayout::ShmTotalSize` (Shared/include/apm44/ShmRingLayout.h
  line 48) — the canonical "minimum size for declared capacity"
  computation.
- `tests/test_mmap_shm_ring.cpp` and `test_shm_object_identity.cpp`
  — existing test fixtures for the shm ring; use isolated names
  like `/apm44t<pid>f`.

### Established Patterns
- `MmapShmRing` already exposes `lastErrorCode` and `lastError()`
  — tests assert on these strings.
- `MmapShmRing::create` (the producer path) writes a valid header
  and uses `header->header_bytes = sizeof(ShmRingHeader)`. The
  consumer's `open` path can trust this for objects the daemon
  itself created, but objects from the driver (HAL) need full
  validation.
- `ValidateShmHeader` in `ShmRingLayout.h` already does most of the
  field-level validation (magic, version, channels, capacity != 0,
  header_bytes >= sizeof(ShmRingHeader)). It does NOT check the
  total object size.

### Integration Points
- `MmapShmRing::open()` is called from `VirtualDeviceFeed::open`
  (consumer role) and from the daemon's input thread paths
  (consumer role). Producer role is only the driver via
  `ShmIoHandler`.
- `MmapShmRing::isMappedObjectStale()` is called by
  `VirtualDeviceFeed::isRingStale` and `pollStaleRing`, which
  decides whether to remap.
- The error string from `lastError()` propagates to
  `BridgeProcessManager.bridgeFailureMessage` in the app UI — so
  bounded, safe diagnostic strings are doubly important.

### Hotspots

- `MmapShmRing.cpp:130-176` — `open()`: the size check is at
  line 145 (`st.st_size <= 0`); the `mmap` at line 157 succeeds
  for objects of any positive size; the header is read at line
  167 without verifying the object is large enough to hold it.
- `MmapShmRing.cpp:46-59` — `DescribeHeaderMismatch`: prints
  `header.producer_build_id` (a `char[64]`) directly into an
  `ostringstream`. The `operator<<(ostream&, const char*)`
  overload stops at the first null, so the operator will not read
  past a null. But it WILL read whatever uninitialised bytes are
  between the actual ID and the first null — and the field is
  never zeroed by the consumer. The risk is that the producer
  fills the field with a non-null-terminated string (truncated by
  `strncpy` if the source was longer than 63 chars), and the
  consumer's diagnostic prints the entire 64-byte region until it
  finds a null — which may include the producer's adjacent header
  fields. Better to bound explicitly.
- `MmapShmRing.cpp:193-202` — `isMappedObjectStale`: the
  `ShmObjectIdentityChanged` check does not include size.

</code_context>

<specifics>
## Specific Ideas

- For SHM-01/02, add a single early-out in `open()`:
  ```cpp
  if (static_cast<std::size_t>(st.st_size) < sizeof(ShmRingHeader)) {
    recordError(ShmRingErrorCode::HeaderTruncated,
                "shm object is smaller than ShmRingHeader");
    close();
    return false;
  }
  ```
  followed by:
  ```cpp
  header_ = static_cast<ShmRingHeader*>(base_);
  if (!ValidateShmHeader(*header_)) { ... }
  // New SHM-02 check: declared capacity vs mapped size
  if (static_cast<std::size_t>(st.st_size) <
      ShmTotalSize(header_->capacity_frames)) {
    recordError(ShmRingErrorCode::CapacityExceedsObject,
                "shm object too small for declared capacity");
    close();
    return false;
  }
  ```
- For SHM-03, extend `ShmObjectIdentity` to include the size
  captured at mapping time, and let `ShmObjectIdentityChanged`
  also compare sizes. This is one-line in the identity struct
  plus an `if (mapped.size != current.size)` in the changed
  check.
- For SHM-04, replace the bare `<<` on `producer_build_id` with:
  ```cpp
  char prodId[kShmBuildIdBytes + 1] = {};
  std::strncpy(prodId, header.producer_build_id, kShmBuildIdBytes);
  std::string prodIdStr(prodId, strnlen(prodId, kShmBuildIdBytes));
  if (prodIdStr.empty()) prodIdStr = "<unterminated>";
  out << "producer_build_id='" << prodIdStr << "'";
  ```
  The key is `strnlen` — bounded by `kShmBuildIdBytes`, so it
  cannot read past the field. Do the same for the consumer's
  `kBuildId` rendering (it is a string literal so the size is
  known at compile time, but apply the same pattern for
  consistency).
- For SHM-05, four test cases in `test_mmap_shm_validation.cpp`:
  1. `OpenRejectsTruncatedObject` — `shm_open` a name, `ftruncate`
     to 32 bytes (less than `sizeof(ShmRingHeader)`), then open
     and assert `lastErrorCode == HeaderTruncated`.
  2. `OpenRejectsValidHeaderWithHugeCapacity` — write a valid
     header but declare `capacity_frames = 1_000_000` while the
     object is `ShmTotalSize(4096)` in size. Open and assert
     `lastErrorCode == CapacityExceedsObject`.
  3. `OpenAcceptsHeaderOnlyLargerThanSize` — actually this is
     fine; the inverse. Skip.
  4. `HeaderMismatchDiagnosticHandlesUnterminatedBuildId` — write a
     header with `producer_build_id` filled with `'X'` for the
     full 64 bytes (no null). Open and assert the diagnostic
     string either stops at the first embedded null or marks the
     value as `<unterminated>` and does not read past 64 bytes.
  5. (Optional) `OpenAcceptsCorrectlySizedObject` — sanity
     baseline.

  Tests use isolated names: `/apm44_validation_<pid>_<index>`.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>
