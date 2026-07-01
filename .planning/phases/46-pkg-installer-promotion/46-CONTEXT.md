# Phase 46: PKG Installer Promotion - Context

**Gathered:** 2026-07-01
**Status:** Ready for planning
**Mode:** Smart discuss defaults auto-accepted by user instruction

<domain>
## Phase Boundary

Promote the existing optional package installer path into a public-release
quality, fail-closed `.pkg` flow. This phase owns package creation, installer
identity enforcement, package notarization/stapling/Gatekeeper validation,
payload integrity, and first-install/upgrade replacement behavior for the app
and HAL driver. It does not own the final polished DMG wrapper, public docs, or
GitHub publication except where Phase 46 must expose durable package gates for
later phases to compose.

</domain>

<decisions>
## Implementation Decisions

### Public Package Contract
- The signed `.pkg` becomes a required public release artifact for this
  milestone, not an optional `APM44_BUILD_PKG=1` side path.
- Release mode must fail before publication when the Developer ID Installer
  identity is missing, ambiguous, or does not actually sign the package.
- Local-only or maintainer-experiment package output may exist only behind an
  explicit local-development override and must be labeled as not publishable.
- Package validation must include `pkgutil --check-signature`, `spctl --assess
  --type install`, notarization acceptance, stapling, and stapler validation.

### Payload and Upgrade Behavior
- The package payload must be built from the final signed/stapled app and HAL
  driver artifacts, preserving extended attributes rather than rebuilding loose
  or unstapled copies.
- The package installs `APM44 Bridge.app` to `/Applications` and
  `APM44Bridge.driver` to `/Library/Audio/Plug-Ins/HAL` with root-owned HAL
  permissions.
- Upgrade behavior must replace stale app/helper/driver state from the current
  latest public release rather than leaving parallel or ambiguous installed
  files.
- Postinstall may reload Core Audio and open the app best-effort, but release
  proof must not depend on best-effort UI launch succeeding.

### Release Gate Composition
- `scripts/release-all.sh` should orchestrate the package gate in the normal
  notarized release path so Phase 47 can wrap the validated package into the
  final DMG.
- Package checksum and provenance should be generated only after package
  stapling, matching the final bytes later published or wrapped.
- Tests should use fake `security`, `productsign`, `pkgutil`, `spctl`, and
  `xcrun stapler/notarytool` behavior where possible so fail-closed release
  order is CI-testable without Apple credentials.
- The release scripts should keep the existing explicit local-only
  unnotarized override, but public package claims require real notary/profile
  readiness and installer signing.

### Certificate and Operator Setup
- If no usable Developer ID Installer identity exists on this machine, the
  phase must record a blocker or setup path; it must not silently downgrade the
  public release contract.
- Existing CSR/import helper scripts may be reused, but certificate/private-key
  material and local signing artifacts must remain untracked and ignored.
- Error messages should tell the maintainer exactly which identity/profile is
  missing and which setup script or Apple Developer step to run.
- Operator-owned target-hardware soak remains out of scope for Phase 46; this
  phase proves package construction and package-level install readiness.

### the agent's Discretion
The agent may choose the smallest structural script/test changes that make the
package path fail closed and composable with later DMG/install/publication
phases. Prefer extending existing scripts over adding a parallel packaging
framework unless the current script shape blocks signed/notarized package
promotion.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/build-release-pkg.sh` already stages `APM44 Bridge.app` and
  `APM44Bridge.driver`, builds an unsigned package with `pkgbuild`, imports the
  Apple Developer ID G2 CA, and signs with `productsign` when a Developer ID
  Installer identity is found.
- `scripts/notarize-release-pkg.sh` already uses the shared
  `scripts/notary-result.sh` fail-closed helper, staples the package, and
  validates the stapled ticket.
- `scripts/release-all.sh` already performs the signed app/driver evidence zip,
  staples inner artifacts, rebuilds the final DMG from stapled payloads, and has
  an optional package branch.
- `tests/test_release_scripts.sh` already fakes Apple tooling and verifies
  notary, stapling, release ordering, checksum, workflow, and package-related
  behavior without credentials.
- `scripts/create-installer-csr.sh` and `scripts/install-installer-cert.sh`
  already document the Developer ID Installer certificate setup path.

### Established Patterns
- Release scripts use `set -euo pipefail`, explicit environment overrides, and
  fail-closed behavior for public artifact gates.
- Notarization acceptance is centralized through `require_notary_accepted`.
- Public-release proof prefers scripted validation and regression tests over
  unchecked manual claims.
- Local-only overrides are allowed when clearly labeled and kept out of public
  artifact claims.

### Integration Points
- `scripts/release-all.sh` is the main orchestration point for package promotion.
- `scripts/build-release-pkg.sh` is the package construction and installer
  identity boundary.
- `scripts/notarize-release-pkg.sh` is the package notary/stapling validation
  boundary.
- `tests/test_release_scripts.sh` is the credential-free release-script
  regression suite.
- Later phases will consume the package artifact in `build/signing` and expect
  it to be validated before the final DMG layout is built.

</code_context>

<specifics>
## Specific Ideas

- Treat `APM44_BUILD_PKG=1` as obsolete for public release mode unless retained
  only as an explicit compatibility/local toggle.
- Add direct signature and Gatekeeper package checks close to package creation
  and notarization, not only in docs.
- Make ambiguous multiple Developer ID Installer identities fail with an
  explicit `INSTALLER_SIGN_ID` instruction.
- Ensure the package build never leaves an unsigned package at the final public
  package path in release mode.

</specifics>

<deferred>
## Deferred Ideas

- Phase 47 owns replacing the raw DMG folder view with a PKG-first professional
  mounted layout.
- Phase 48 owns installing from the final mounted DMG/PKG path and proving
  installed app/helper/HAL sync on the live system.
- Phase 49 owns public documentation and full release-hygiene text updates.
- Phase 50 owns GitHub latest release publication and downloaded-asset proof.

</deferred>
