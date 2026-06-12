# Phase 14: Release Automation Fail-Closed - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 14 closes release automation blockers before public distribution and final
validation. It is limited to notarization script failure contracts,
`release-all.sh` credential handling, signing workflow build verification, and
credential-free regression coverage for the release scripts.

</domain>

<decisions>
## Implementation Decisions

### Notary Result Contract
- DMG and PKG release notarization must require both a successful
  `xcrun notarytool submit` exit status and parsed `status: Accepted` output.
- Any rejected, auth-failed, network-failed, or malformed notary output fails
  closed before stapling.
- Notarization scripts must print the original submit output and attempt to
  fetch a notary log when an id is available.
- The notary parsing path should stay shell-native and dependency-free so it can
  run on maintainer machines and GitHub macOS runners.

### Release-All Default
- `scripts/release-all.sh` is a public-release command, so missing notary
  credentials are fatal by default.
- The only credential-free path is an explicit local-only override:
  `APM44_ALLOW_UNNOTARIZED=1`.
- Override output must be visibly labelled as local-only and unnotarized so it
  cannot be mistaken for a public release artifact.
- The optional PKG path remains behind `APM44_BUILD_PKG=1`.

### Signing Workflow Strictness
- `.github/workflows/sign-notarize.yml` must not mask
  `scripts/verify-app-build.sh` failures.
- The workflow can still skip signing or notarization when credentials are not
  present, but build verification failures must stop the job.

### Regression Strategy
- Add a credential-free shell test runner under `tests/` that prepends fake
  `xcrun` and `security` executables to `PATH`.
- Cover accepted, rejected, auth-failure, network-failure, malformed
  `notarytool` output, missing notary credentials, and explicit unnotarized
  override behavior without contacting Apple.
- Wire the shell tests into `scripts/ci.sh` after native tests and before app
  validation so local and CI gates share the same release-script safety checks.

### the agent's Discretion
The agent may introduce a small shared shell helper for notarization parsing if
it reduces duplication between DMG and PKG scripts without changing their public
entrypoints.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/notarize-release-dmg.sh` and `scripts/notarize-release-pkg.sh`
  already own final artifact notarization and stapling.
- `scripts/release-all.sh` already coordinates build, sign, notary dry run,
  stapling, final DMG notarization, and optional PKG packaging.
- `.github/workflows/sign-notarize.yml` is the manual signing/notarization
  workflow near Apple credentials and release artifacts.
- `scripts/ci.sh` is the local/CI validation command that does not require
  Apple credentials.

### Established Patterns
- Shell scripts use `set -euo pipefail`, root-relative paths, and plain Bash
  conditionals.
- Existing CI validation is script-first rather than a separate test framework.
- Release scripts already use environment variables for maintainer-specific
  paths and credentials.

### Integration Points
- Notarization scripts call `xcrun notarytool submit --wait`, `xcrun stapler
  staple`, and `xcrun stapler validate`.
- `release-all.sh` currently probes credentials with `xcrun notarytool history`.
- The signing workflow currently runs `bash scripts/verify-app-build.sh || true`
  inside the release artifact build step.
- `scripts/check-secrets.sh` scans shell test fixtures, so fake credential data
  must avoid secret-like literals.

</code_context>

<specifics>
## Specific Ideas

Use the accepted Phase 14 technical defaults: strict notary status parsing,
missing-credential hard failure by default, explicit local-only override, strict
workflow app-build verification, and mocked shell tests with fake `xcrun`.

</specifics>

<deferred>
## Deferred Ideas

- Full live notarization evidence is deferred to Phase 16 because it depends on
  maintainer Apple credentials and the final release validation sequence.
- Public installer/README UX and security posture language is deferred to Phase
  15.

</deferred>
