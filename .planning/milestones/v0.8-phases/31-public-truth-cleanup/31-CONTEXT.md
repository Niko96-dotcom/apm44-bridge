# Phase 31: Public Truth Cleanup - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Public docs and user-facing code must not present stale milestone language, stale artifact commands, wrong latency defaults, dead converter files, or SRC quality choices that duplicate behavior.

</domain>

<decisions>
## Implementation Decisions

### Release and Latency Truth
- Keep artifact version `0.1.1` as the current product artifact story unless `APM44_VERSION` overrides it.
- Replace stale v0.4 release-closeout language with current v0.8 release-candidate language.
- Preserve Safe as the fresh-install latency default and keep docs aligned with that default.

### SRC Quality Truth
- Keep Standard / High / Best visible, but make them map to distinct converter behavior and latency estimates.
- Regression-test public SRC quality labels so they cannot silently collapse to the same estimated behavior.

### the agent's Discretion
No source converter files require deletion because the legacy converter source exists only in ignored build outputs, not the tracked source tree.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BridgeDaemon/src/engine/LibSamplerateSrc.cpp` owns libsamplerate converter selection.
- `BridgeDaemon/src/engine/BridgeMetrics.h` owns public latency group-delay estimates.
- `tests/test_bridge_metrics_json.cpp` already validates metrics JSON behavior.

### Established Patterns
- Docs use `APM44_VERSION:-0.1.1` for overrideable artifact commands in release tooling.

### Integration Points
- `docs/release.md`, `docs/release-validation.md`, `docs/install.md`
- `BridgeDaemon/src/engine/LibSamplerateSrc.cpp`, `BridgeDaemon/src/engine/BridgeMetrics.h`
- `tests/test_bridge_metrics_json.cpp`, `docs/menu-bar-qa.md`

</code_context>

<specifics>
## Specific Ideas

Use `SRC_SINC_FASTEST`, `SRC_SINC_MEDIUM_QUALITY`, and `SRC_SINC_BEST_QUALITY` for Standard, High, and Best respectively.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>
