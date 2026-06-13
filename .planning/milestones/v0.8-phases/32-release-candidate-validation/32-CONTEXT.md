# Phase 32: Release Candidate Validation - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Close v0.8 with final regression evidence and recorded release-Mac plus target-hardware validation commands. Operator-dependent hardware validation may remain a recorded external action, but code-level blockers must be closed.

</domain>

<decisions>
## Implementation Decisions

### Regression Evidence
- Use `bash scripts/ci.sh` as the comprehensive local release-candidate gate.
- Record evidence from the final run after all v0.8 edits.

### Release-Mac Commands
- Store exact commands for secrets, build, signing, notarization, stapling, Gatekeeper assessment, installed HAL checks, installed app/helper sync, and shm status.

### Target Hardware Commands
- Store clean DMG install, HAL visibility, menu-bar app start, Cubase route, smoke/soak, and export-rate proof expectations.

### the agent's Discretion
Operator-owned hardware validation can be documented rather than executed on this development machine.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/ci.sh` is the repo-local release-candidate gate.
- `docs/release-validation.md` is the canonical release validation checklist.
- `docs/first-run-cubase.md` and `docs/cubase-soak.md` cover operator hardware steps.

### Established Patterns
- Hardware-dependent release items are recorded as operator action when target hardware or Apple credentials are unavailable.

### Integration Points
- `docs/release-validation.md`
- `.planning/REQUIREMENTS.md`
- `scripts/ci.sh`

</code_context>

<specifics>
## Specific Ideas

Record commands directly in `docs/release-validation.md` under release-Mac and target-hardware sections.

</specifics>

<deferred>
## Deferred Ideas

Live Cubase/AirPods target-hardware soak remains operator-dependent.

</deferred>
