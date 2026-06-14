# Phase 33: ASBD Memory Contract - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 33 tightens only the Core Audio ASBD acceptance contract used before IOProc code trusts Float32 stereo buffer layout. The phase does not change sample-rate policy, channel count, resampling, or HAL negotiation behavior beyond rejecting byte layouts that do not match the memory layout the code reads.

</domain>

<decisions>
## Implementation Decisions

### Contract Enforcement
- Keep the existing sample-rate, linear PCM, Float32, stereo, and 32-bit checks intact.
- Reject every accepted ASBD whose `mFramesPerPacket` is not exactly `1`.
- Treat the `kAudioFormatFlagIsNonInterleaved` flag as the branch point for byte layout validation.
- Preserve acceptance for USB/AirPods-style interleaved packed Float32 stereo when `mBytesPerFrame == sizeof(float) * 2` and `mBytesPerPacket == sizeof(float) * 2`.

### Regression Shape
- Add targeted unit coverage in `tests/test_audio_formats.cpp` rather than widening release-script tests.
- Cover wrong interleaved byte-size fields, missing packed interleaved format, wrong non-interleaved byte-size fields, and wrong frames-per-packet.
- Keep regression cases close to the helper that constructs the ASBDs so future maintainers can see the exact memory contract.

### the agent's Discretion
Use small local helper functions in the test file if they keep the regression setup readable.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Shared/src/AudioFormats.cpp` contains `AsbdMatchesFloat32Stereo` and `AsbdMatchesFloat32StereoNonInterleaved`.
- `MakeFloat32StereoNonInterleaved` already constructs the accepted non-interleaved layout.
- `tests/test_audio_formats.cpp` already covers the existing AirPods-style interleaved acceptance case.

### Established Patterns
- Native tests use Catch2 `TEST_CASE`, `REQUIRE`, and `REQUIRE_FALSE`.
- Existing ASBD tests construct plain `AudioStreamBasicDescription` values inline.

### Integration Points
- `BridgeDaemon/src/hal/FormatNegotiator.cpp` relies on `AsbdMatchesFloat32Stereo` before audio buffers are accepted.
- The phase verification can use the native `test_audio_formats` target and then the full `scripts/ci.sh` gate later in Phase 37.

</code_context>

<specifics>
## Specific Ideas

Rejecting strange byte layouts is the point of this phase. The code should not merely check Float32 stereo metadata while leaving packet/frame byte counts unconstrained.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>
