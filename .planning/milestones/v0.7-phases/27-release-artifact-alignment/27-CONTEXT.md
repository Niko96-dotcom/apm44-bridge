# Phase 27: Release Artifact Alignment - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase)

<domain>
## Phase Boundary

Align the manual signing workflow and local CI so they build, embed, sign, and verify the exact Release app bundle at `build/Release/APM44 Bridge.app`.

</domain>

<decisions>
## Implementation Decisions

### the agent's Discretion
- Keep the signing workflow credential-gated, but make the unsigned build artifact path deterministic before the signing step.
- Reuse `scripts/verify-app-build.sh` as the app-build proof entrypoint, extending it only enough to support a fixed output directory.
- Make `scripts/ci.sh` fail if an app bundle was built but the expected app or embedded daemon under test is missing.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/sign-notarize.yml` already performs release signing and codesign verification.
- `scripts/verify-app-build.sh` already generates the Xcode project and proves the app executable exists.
- `scripts/embed-daemon-in-app.sh` and `scripts/verify-installed-sync.sh` already accept `APM44_APP_PATH`.

### Established Patterns
- Release-script behavior is regression-gated in `tests/test_release_scripts.sh` using credential-free source checks and fakes.
- Local CI uses `scripts/ci.sh` as the comprehensive gate.

### Integration Points
- `APM44_APP_OUTPUT_DIR` lets the workflow and CI place the app in `build/Release`.
- `APM44_APP_PATH` threads the same app bundle into embed, signing, and installed-sync checks.

</code_context>

<specifics>
## Specific Ideas

No additional user-specific requirements; follow v0.7 requirements SIGN-01 through CI-03.

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>
