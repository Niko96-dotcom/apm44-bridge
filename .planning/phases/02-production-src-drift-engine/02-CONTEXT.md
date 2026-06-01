# Phase 2: Production SRC & Drift Engine - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning
**Mode:** Smart discuss (yolo — recommended answers accepted)

<domain>
## Phase Boundary

Replace Phase 1 fixed-ratio `AudioConverter` path with **libsamplerate** streaming SRC at nominal 160/147 ratio plus variable `src_ratio` for drift. Add lock-free SPSC ring between input and output IOProcs with configurable target fill (~10–20 ms default). Implement drift controller (±500 ppm) to prevent buffer runaway/starvation. Validate 30+ minute soak stability (automated soak test where possible; human soak optional). Keep BlackHole MVP routing; no menu bar UI or HAL driver changes.

</domain>

<decisions>
## Implementation Decisions

### libsamplerate integration
- Vendor libsamplerate **0.2.2** as git submodule under `third_party/libsamplerate` (or FetchContent) — static link into `apm44-bridge`
- Use `src_new(SRC_SINC_MEDIUM_QUALITY, 2, ...)` for default; CLI flag `--src-quality` maps medium/high/best for future Phase 3 presets
- Persistent `SRC_STATE` per channel pair; `src_process` in output IOProc pulls from ring
- Nominal `src_ratio = 48000.0 / 44100.0`; drift nudges ratio smoothly (low-pass on ratio changes)

### Ring buffer & timing
- Upgrade `PlanarRingBuffer` to lock-free SPSC with power-of-two capacity; track fill in samples @ 44.1 side
- Target fill default **15 ms** at 44.1 kHz (~662 samples); CLI `--target-fill-ms` (10–40 range)
- Input IOProc: push only; Output IOProc: pop + SRC + write; never cross-call mutex

### Drift controller
- PI-style controller on ring fill error vs target; output = ppm adjustment added to nominal ratio
- Clamp total ratio adjustment to **±500 ppm** relative to nominal
- Expose metrics on non-RT thread: current fill ms, effective ratio, underrun/overrun counts

### Migration from Phase 1
- Remove or gate `AudioConverterSrc` behind `--legacy-converter` debug flag (default off)
- Keep device discovery/preflight from Phase 1 unchanged
- Extend unit tests: SRC ratio drift simulation, ring fill controller, soak test binary `apm44-soak` (runs N minutes offline with synthetic clocks)

### Soak validation
- Add `tests/test_drift_controller.cpp` and offline soak harness feeding synthetic sine with clock skew
- Document human 30+ min soak in `docs/soak-test.md`; CI runs shortened 60s soak only

### Claude's Discretion
- Exact PI gains and smoothing time constants
- Whether input/output block sizes differ

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BridgeDaemon/src/engine/BridgeEngine.cpp`, `IoProcHandlers.cpp`, `AudioConverterSrc.cpp`
- `Shared/include/apm44/PlanarRingBuffer.h`
- CMake + Catch2 test harness from Phase 1

### Established Patterns
- C++20 RT path; logging off hot path
- HAL dual IOProc architecture

### Integration Points
- Replace converter stage between ring read and AirPods write
- Drift metrics feed future XPC/menu bar (Phase 3)

</code_context>

<specifics>
## Specific Ideas

- Follow STACK.md: libsamplerate `src_set_ratio` / smooth ratio for drift
- QA-01 (30+ min) is primary success criterion — prioritize soak harness

</specifics>

<deferred>
## Deferred Ideas

- Menu bar latency presets (Phase 3)
- HAL virtual device (Phase 4)
- Signed distribution (Phase 5)

</deferred>
