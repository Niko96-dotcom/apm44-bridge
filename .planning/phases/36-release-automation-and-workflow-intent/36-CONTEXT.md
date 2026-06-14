# Phase 36: Release Automation and Workflow Intent - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 36 hardens release automation truth. The one-command maintainer release path must run strict codesign verification before notarization, and the manual GitHub workflow must be clear that it is maintainer signing/notary evidence unless artifact upload/publication is explicitly added.

</domain>

<decisions>
## Implementation Decisions

### Release Automation Gate
- Insert `bash scripts/codesign-verify-release.sh` in `scripts/release-all.sh` after signed artifacts exist and before `scripts/notary-dry-run.sh`.
- Preserve `APM44_ALLOW_UNNOTARIZED=1` as a local-only packaging override that skips notarization and therefore does not run the strict pre-notary gate.
- Extend release-script tests to prove the strict gate runs before the first notary submit path.

### GitHub Workflow Intent
- Keep `.github/workflows/sign-notarize.yml` manual and credential-gated.
- Label it as maintainer signing/notary evidence, not the public artifact publication path.
- Clarify in docs that the public DMG still comes from `scripts/release-all.sh` on a maintainer Mac unless artifact upload is intentionally added later.

### the agent's Discretion
Use comments and test assertions rather than renaming the workflow file; the existing path is already referenced by release docs and tests.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/release-all.sh` already sequences build/sign/DMG, notary dry-run, stapling, final DMG packaging, and DMG notarization.
- `tests/test_release_scripts.sh` fakes `xcrun`, `security`, `codesign`, and selected shell script calls for credential-free release flow checks.
- `.github/workflows/sign-notarize.yml` signs and optionally notarizes but does not upload signed artifacts.

### Established Patterns
- Release automation tests inspect the fake xcrun log for command order.
- Workflow trust decisions are documented in `docs/release.md`.

### Integration Points
- The strict gate belongs between `bash scripts/build-release-dmg.sh` and `bash scripts/notary-dry-run.sh` in the notary-ready branch.

</code_context>

<specifics>
## Specific Ideas

Make the fake test log include `bash scripts/codesign-verify-release.sh`, then assert it occurs before `bash scripts/notary-dry-run.sh`.

</specifics>

<deferred>
## Deferred Ideas

Uploading signed/notarized artifacts from GitHub Actions remains future work.

</deferred>
