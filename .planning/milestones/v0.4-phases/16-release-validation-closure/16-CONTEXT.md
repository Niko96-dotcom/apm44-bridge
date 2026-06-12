# Phase 16: Release Validation Closure - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 16 closes v0.4 by producing a repeatable public-release validation record:
final automated gates, the exact clean-build-through-Gatekeeper command
sequence, artifact checks for the DMG-primary path, and exact unblock commands
for Apple credential, certificate, hardware, or operator-dependent steps.

</domain>

<decisions>
## Implementation Decisions

### Validation Posture
- Treat `bash scripts/ci.sh` as the final credential-free automated verification gate for QA-01.
- Treat live Apple notarization, stapling tickets, and Gatekeeper assessment as public-release blocking when credentials are present, and as explicitly blocked with exact unblock commands when credentials are absent.
- Keep DMG-primary as the public artifact path; PKG remains maintainer-only unless `APM44_BUILD_PKG=1` and Developer ID Installer validation are intentionally run.
- Do not silently mark unavailable Apple-service or hardware checks as complete.

### Release Evidence
- Record the command sequence from clean build through signing, notary submission, stapling, DMG validation, and Gatekeeper assessment in a public maintainer doc.
- Record this machine's current live evidence in Phase 16 SUMMARY and VERIFICATION artifacts.
- Label `APM44_ALLOW_UNNOTARIZED=1` output as local-only and not public-release-ready.
- Keep previous v0.2/v0.3 hardware-dependent gaps visible as release caveats if they are not re-run on real hardware.

### the agent's Discretion
- Choose the smallest docs/script changes needed to make validation repeatable and auditable.
- Prefer existing scripts (`ci.sh`, `release-all.sh`, `codesign-verify-release.sh`, `notarize-release-dmg.sh`, `verify-installed-sync.sh`) over inventing a parallel release pipeline.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/ci.sh` runs secret scan, CMake configure/build, native tests, release-script tests, Swift app build/tests, helper embedding, and installed-sync dry-run.
- `scripts/release-all.sh` is the maintainer release command and fails closed without notary credentials unless `APM44_ALLOW_UNNOTARIZED=1`.
- `scripts/codesign-verify-release.sh` verifies daemon, app, and driver signatures and hardened runtime signals.
- `scripts/notarize-release-dmg.sh` notarizes, staples, and validates the final DMG using the shared fail-closed notary helper.
- `docs/release.md` already documents the intended order for app/driver evidence zip, inner stapling, final DMG packaging, and final DMG notarization.

### Established Patterns
- Release blockers are closed by combining source/script changes, mocked credential-free regression tests, public docs, and local GSD verification artifacts.
- `.planning/` remains ignored but selected GSD artifacts are force-added for continuity.
- Live Apple or hardware checks are accepted only when the exact unblock command is captured.

### Integration Points
- `docs/release-validation.md` should be the repeatable maintainer validation record/checklist.
- `docs/release.md` should point maintainers to the validation record without duplicating every detail.
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, and `.planning/STATE.md` are updated by GSD phase completion.

</code_context>

<specifics>
## Specific Ideas

Use today's local machine state as evidence, including current git build ids,
credential availability, build/test output, and release-artifact assessment.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within phase scope.

</deferred>
