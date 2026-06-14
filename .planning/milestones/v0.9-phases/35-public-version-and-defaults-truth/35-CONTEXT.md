# Phase 35: Public Version and Defaults Truth - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 35 normalizes public documentation truth for the current 0.1.1 DMG-primary release identity, the Safe fresh-install latency default, and the actual HAL driver build path. It does not change marketing version, app behavior, release packaging, or installer flow.

</domain>

<decisions>
## Implementation Decisions

### Version Identity
- Keep `0.1.1` as the current public artifact/app version because scripts, app metadata, changelog, install docs, and issue template already converge on it.
- Update stale milestone wording in release validation from v0.8 to v0.9 public-polish validation.
- Keep `APM44Bridge-${APM44_VERSION:-0.1.1}.dmg` as the variable-form release command pattern.

### Defaults and Paths
- Public docs and QA checklists must say Safe is the fresh-install default, matching `BridgeSettings`.
- Release docs must use `build/Driver/APM44Bridge.driver`, matching scripts and CI.
- Add source-level release-script tests for the stale claims so they fail if reintroduced.

### the agent's Discretion
Use documentation/test guard changes only; no runtime behavior changes are needed.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `App/APM44Bridge/BridgeSettings.swift` defaults `latencyPreset = .safe` when no stored default exists.
- `scripts/build-release-dmg.sh`, `scripts/sign-release.sh`, and `scripts/codesign-verify-release.sh` use `build/Driver/APM44Bridge.driver`.
- `tests/test_release_scripts.sh` already contains source-level release workflow guards.

### Established Patterns
- Public release docs use `APM44_VERSION:-0.1.1` for generated DMG paths.
- Release script tests use `assert_contains` and `assert_not_contains` helpers.

### Integration Points
- `docs/install.md`, `docs/menu-bar-qa.md`, `docs/release.md`, and `docs/release-validation.md` are the public-truth surfaces for this phase.

</code_context>

<specifics>
## Specific Ideas

Patch the stale statements directly and guard against their return in `tests/test_release_scripts.sh`.

</specifics>

<deferred>
## Deferred Ideas

Future version bumps remain outside this phase; this phase records that 0.1.1 is still the current public artifact identity.

</deferred>
