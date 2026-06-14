# Phase 41: Regression and Release Validation Closure - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 41 closes v1.0 with regression/source-audit proof, full local CI, installed-sync validation where possible, and truthful operator-owned Cubase/AirPods soak evidence.

</domain>

<decisions>
## Implementation Decisions

### Validation Closure
- Treat `scripts/ci.sh` as the authoritative local release/build gate.
- Run installed-sync and HAL-driver verification entrypoints where the machine permits them.
- Record target Cubase 15 and USB-C AirPods Max validation as operator-owned when live hardware/operator proof is unavailable.
- Reconcile all v1.0 requirement IDs before milestone closeout.

### the agent's Discretion
Do not invent live hardware evidence; record automated proof and explicit operator-owned caveats.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/ci.sh` is the full repo truth gate.
- `scripts/verify-installed-sync.sh`, `scripts/verify-hal-driver.sh`, and `apm44-bridge --shm-status` are the trusted installed-system entrypoints.
- Prior milestone closeouts already use verification artifacts to document hardware-blocked evidence truthfully.

### Established Patterns
- Requirements are marked complete only after code/docs/tests and verification evidence line up.
- Operator-owned release validation remains explicit rather than fabricated.

### Integration Points
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, and `.planning/STATE.md` must agree before lifecycle closeout.

</code_context>

<specifics>
## Specific Ideas

Record exact commands and outcomes in `41-VERIFICATION.md`, including any operator-owned live Cubase/AirPods checklist.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
