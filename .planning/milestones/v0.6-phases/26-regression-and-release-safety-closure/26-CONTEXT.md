# Phase 26: Regression and Release Safety Closure - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 26 closes v0.6 by wiring release-script regressions into public GitHub CI and running the local validation gates that prove all v0.6 release-safety fixes are covered.

</domain>

<decisions>
## Implementation Decisions

### Public CI Release-Script Coverage
- Add `bash tests/test_release_scripts.sh` to `.github/workflows/ci.yml` after native tests.
- Keep Swift app build/tests after release-script regressions.
- Add a guard in `tests/test_release_scripts.sh` so the workflow fails if this CI step is removed.
- Preserve existing CI-01 action trust markers and official-action-only policy.

### Final Validation
- Use the repo's comprehensive local CI gate as the final proof.
- Record native, Swift, release-script, and traceability evidence in the Phase 26 verification artifact.
- Treat live hardware/operator soak as out of scope per v0.6 requirements.

### the agent's Discretion
The agent may use line-order shell checks for the CI guard because they are deterministic and match the existing release-script regression style.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/ci.yml` already runs secret scan, CMake build, native tests, Swift app build, and Swift unit tests.
- `scripts/ci.sh` already runs `bash tests/test_release_scripts.sh` locally after native tests.
- `tests/test_release_scripts.sh` already contains source/order guards for release automation and workflow trust.

### Established Patterns
- Release-script tests are credential-free and use fake command shims where command execution is needed.
- Workflow source guards check for required commands and fail closed on missing trust markers.
- Full local validation should use `bash scripts/ci.sh`.

### Integration Points
- GitHub CI native job is the release-facing public test surface.
- CI-02 is the only Phase 26 requirement.
- v0.6 traceability lives in `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, and phase verification artifacts.

</code_context>

<specifics>
## Specific Ideas

Add a "Release script tests" step after "Native tests" in `.github/workflows/ci.yml`, then add a `run_ci_02_release_script_tests_in_github_ci` guard to `tests/test_release_scripts.sh`.

</specifics>

<deferred>
## Deferred Ideas

None - Phase 26 is the release-safety closure phase.

</deferred>
