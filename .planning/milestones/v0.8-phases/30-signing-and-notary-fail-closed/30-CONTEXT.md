# Phase 30: Signing and Notary Fail-Closed - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Manual release signing and driver-only notarization must fail closed when required build artifacts or Apple credentials are missing. The phase covers `.github/workflows/sign-notarize.yml`, `scripts/notarize-hal-driver.sh`, and release-script regression coverage.

</domain>

<decisions>
## Implementation Decisions

### Signing Workflow
- Build both `apm44-bridge` and `APM44Bridge` before app signing and verification.
- Treat missing `APPLE_SIGN_ID` as a release workflow error, not a successful skip.
- Treat missing `AC_NOTARY` as a release workflow error when `notarize=true`.
- Keep local credential-free testing in `tests/test_release_scripts.sh`.

### Driver Notarization
- Reuse `scripts/notary-result.sh` and `require_notary_accepted` for HAL driver notarization.
- Preserve driver stapling and validation after accepted notarization.
- Regression-test accepted and rejected driver-only notary paths.

### the agent's Discretion
Implementation details may follow existing release-script patterns as long as workflow drift fails tests.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/notary-result.sh` already centralizes fail-closed `notarytool` result handling.
- `tests/test_release_scripts.sh` has fake `xcrun`, `codesign`, and workflow static assertions.

### Established Patterns
- Release scripts use `set -euo pipefail`, explicit artifact environment variables, and static grep guards for workflow regressions.

### Integration Points
- `.github/workflows/sign-notarize.yml`
- `scripts/notarize-hal-driver.sh`
- `tests/test_release_scripts.sh`

</code_context>

<specifics>
## Specific Ideas

Use exact regression strings for build target coverage and missing credential errors.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>
