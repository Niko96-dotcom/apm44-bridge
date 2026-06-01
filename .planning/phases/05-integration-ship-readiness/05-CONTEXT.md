# Phase 5: Integration & Ship Readiness - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning
**Mode:** Smart discuss (yolo)

<domain>
## Phase Boundary

End-to-end validation: DAW @ 44.1 → APM44 Bridge → daemon → AirPods @ 48. Verify export stays 44.1. DAW matrix (Logic + Ableton minimum). Developer ID sign driver + app; notarization dry-run docs. 30+ min stability with full stack.

</domain>

<decisions>
## Implementation Decisions

### Validation
- `docs/daw-matrix.md` checklist with pass/fail columns
- `scripts/validate-export-rate.sh` — bounce test instructions
- CI: build + unit tests + offline soak only; hardware matrix manual

### Signing
- Document `codesign` + `notarytool` steps in `docs/release.md`
- Export entitlements plist for driver and app
- Ad-hoc sign for local dev in install scripts

### Claude's Discretion
- Whether to add GitHub Actions macOS job (compile only)

</decisions>

<code_context>
Full stack from phases 1-4

</code_context>

<specifics>
QA-02, integration success criteria in ROADMAP Phase 5

</specifics>

<deferred>
APM44 Bridge Pro (v2)

</deferred>
