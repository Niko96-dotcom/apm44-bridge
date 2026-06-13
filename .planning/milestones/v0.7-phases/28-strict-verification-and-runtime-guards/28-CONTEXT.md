# Phase 28: Strict Verification and Runtime Guards - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Make release codesign verification fail loudly on weak signing posture by default, while adding compile-time/runtime guardrails for metrics atomics and clean app termination reset.

</domain>

<decisions>
## Implementation Decisions

### the agent's Discretion
- Use a named local override for ad-hoc development codesign checks rather than weakening release defaults.
- Add the metrics lock-free assertion next to the packed `std::atomic<uint64_t>` storage it protects.
- Route clean running-process termination through the central idle transition helper instead of assigning `.idle` directly.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/codesign-verify-release.sh` already centralizes release signing checks.
- `tests/test_release_scripts.sh` already provides fake command fixtures for credential-free release-script tests.
- `BridgeDaemon/src/engine/MetricsPublisher.h` already stores floating metrics as packed `uint64_t` atomics.
- `BridgeProcessManager.transitionToIdle()` already resets pipe handlers, metrics state, state, connection phase, stop reason, waiters, and pending restart.

### Established Patterns
- Release scripts fail closed unless an explicit local override is present.
- Swift app lifecycle regressions live in `tests/test_bridge_process_manager.swift`.

### Integration Points
- `APM44_ALLOW_LOCAL_CODESIGN=1` is the explicit local-development override for ad-hoc/non-runtime signatures.

</code_context>

<specifics>
## Specific Ideas

No additional user-specific requirements; follow v0.7 requirements REL-01, REL-02, METR-01, and APP-01.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
