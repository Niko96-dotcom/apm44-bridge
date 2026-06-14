# Phase 34: Shared-Memory Compatibility Truth - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 34 reconciles the shared-memory compatibility contract between code and public docs. The phase is limited to ring-header compatibility validation and wording around build ID/sample rate truth; it does not change the shm name, permissions model, ring data layout, or DAW routing.

</domain>

<decisions>
## Implementation Decisions

### Compatibility Contract
- Treat `producer_build_id` as a hard compatibility gate because docs already tell operators mismatches fail fast.
- Treat `sample_rate` as a hard compatibility gate for the current HAL ring because the virtual device contract is fixed at 44,100 Hz.
- Keep generation and object identity as stale-mapping diagnostics/detection rather than startup compatibility gates.
- Preserve existing ABI, header size, capacity, channel, and mapped-size validation behavior.

### Documentation Truth
- Update shared-memory wording to name the exact hard gates: ABI version, header size, declared capacity/object size, channels, sample rate, and producer build ID.
- Keep local IPC/security wording clear that validation is integrity-oriented and not authentication or access control.

### the agent's Discretion
Use `InvalidHeader` for sample-rate/build-ID rejection unless a separate error code becomes necessary for clearer operator handling.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Shared/include/apm44/ShmRingLayout.h` defines `ShmRingHeader`, `kBuildId`, and `ValidateShmHeader`.
- `Shared/src/MmapShmRing.cpp` builds diagnostics through `DescribeHeaderMismatch`.
- `tests/test_mmap_shm_validation.cpp` already writes isolated raw shm objects and validates header rejection behavior.

### Established Patterns
- Header validation regressions live in `tests/test_mmap_shm_validation.cpp`.
- Docs describe `/apm44_bridge_ring` as local IPC with integrity checks, not an auth boundary.

### Integration Points
- `MmapShmRing::create` writes the HAL producer build ID and fixed `44100` ring sample rate.
- `MmapShmRing::open` rejects invalid headers before consumers read samples.

</code_context>

<specifics>
## Specific Ideas

The selected contract is enforcement, not documentation-only downgrade: build ID and sample rate mismatches should fail fast when a daemon opens the ring.

</specifics>

<deferred>
## Deferred Ideas

Per-user shm names and privileged broker setup remain future hardening items.

</deferred>
