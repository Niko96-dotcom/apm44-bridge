# Phase 37: Regression and Public Polish Closure - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 37 closes v0.9 by running the repo truth gates, recording final evidence, and preserving exact operator-owned caveats for publication and target hardware. It should not introduce new product scope unless a regression gate exposes a blocker.

</domain>

<decisions>
## Implementation Decisions

### Verification Closure
- Use `bash scripts/ci.sh` as the full repo-local truth gate.
- Keep targeted evidence from Phases 33-36 in the phase verification record.
- Reconcile requirement traceability through `gsd-sdk phase.complete` rather than manual checkbox editing.

### Caveat Wording
- Automated readiness does not claim Apple credential availability, GitHub release upload, or target USB-C AirPods/Cubase soak completion.
- Operator-owned publication and target-hardware validation caveats should remain visible in planning state and release docs.

### the agent's Discretion
If the full CI gate fails, fix only regressions caused by v0.9 changes before rerunning.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/ci.sh` runs secret scan, submodule prep, CMake configure/build, native CTest, release-script tests, Swift app build/tests when available, daemon embedding, and installed-sync dry-run.
- `.planning/STATE.md` already tracks operator-owned publication and live-hardware caveats.

### Established Patterns
- Prior closeout phases record full gate results in `*-VERIFICATION.md`.
- Planning artifacts are committed with `git add -f` because `.planning/` is ignored.

### Integration Points
- Phase 37 closes QA-01 and QA-02 and unlocks milestone lifecycle audit/complete/cleanup.

</code_context>

<specifics>
## Specific Ideas

Run `bash scripts/ci.sh` once after all Phase 33-36 changes are committed, then record the result and complete the phase.

</specifics>

<deferred>
## Deferred Ideas

GitHub release upload, signed PKG promotion, and target-hardware Cubase/AirPods soak remain operator-owned or future scope.

</deferred>
