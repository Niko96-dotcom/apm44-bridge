# Phase 15: Public Distribution UX and Security Posture - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 15 closes public-facing distribution trust issues after release automation
has been made fail-closed. It is limited to public local-IPC security wording,
the v0.4 installer posture, release stapling/order alignment, and GitHub Actions
trust posture for workflows near release artifacts or signing credentials.

</domain>

<decisions>
## Implementation Decisions

### Local IPC Security Wording
- Public docs must say `/apm44_bridge_ring` is local-machine IPC between the HAL
  producer in `coreaudiod` and the user-space daemon consumer.
- Public docs must not describe the shared-memory ring as an authentication,
  authorization, sandbox, or privilege boundary.
- The shm mode `0666` implication must be explicit: other local processes/users
  may be able to open the object while it exists, so no secrets or trust
  decisions belong in the ring.
- Future hardening options should be listed without claiming they are already
  implemented.

### Installer Posture
- Keep the existing project decision: v0.4 remains DMG-primary for public
  distribution.
- PKG tooling stays maintainer-only and tracked as a future release follow-up
  until Developer ID Installer signing, installer UX, and validation are
  complete.
- The DMG admin install flow must read as intentional and professional, not as a
  temporary workbench path.

### Stapling Order
- The final public DMG must contain the exact app and driver artifacts after
  inner stapling/validation.
- `release-all.sh` should package the final DMG after inner app/driver tickets
  are stapled, then notarize/staple/validate the final container.
- Docs must describe the same order as the scripts.

### GitHub Actions Trust Posture
- Critical workflows near release artifacts or signing use official GitHub
  actions today (`actions/checkout`, `actions/upload-artifact`) plus the
  official dependency review action in CI.
- For v0.4, record an explicit trust decision rather than pinning full SHAs:
  official actions remain tag-pinned, Dependabot monitors GitHub Actions weekly,
  and signing/notarization still happens on maintainer machines unless explicit
  runner credentials are configured.
- Document SHA pinning as the future hardening path if the project moves more
  signing or release publication into CI.

### the agent's Discretion
The agent may add a small packaging-only helper or flag if it keeps
`release-all.sh` simple and makes final-DMG contents match the stapled inner
artifacts.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `docs/hal-driver.md` already has an IPC section with the shm name and mode.
- `docs/install.md` already tells end users the DMG is the public artifact and
  PKG is maintainer-only.
- `docs/release.md` already documents `release-all.sh`, manual signing, notary
  dry run, stapling, and optional PKG tooling.
- `scripts/build-release-dmg.sh` builds/signs the app and driver and creates the
  DMG.
- `scripts/release-all.sh` orchestrates the public release path.
- `.github/dependabot.yml` already enables weekly GitHub Actions updates.

### Established Patterns
- Public docs are plain Markdown under `docs/` with direct command snippets.
- Planning decisions are captured in `.planning/PROJECT.md` and phase context.
- Release scripts use Bash with root-relative paths and environment overrides.
- Workflow hardening can be documented when SHA pinning is deferred.

### Integration Points
- `docs/install.md` and `README.md` are the public entrypoints for end users.
- `docs/release.md` is the maintainer source of truth for signing/notarization.
- `scripts/release-all.sh` and `scripts/build-release-dmg.sh` must agree with
  the documented release sequence.
- `.github/workflows/release.yml` and `.github/workflows/sign-notarize.yml` are
  the critical release/signing workflows.

</code_context>

<specifics>
## Specific Ideas

Use the existing project decision: DMG-primary public release, PKG
maintainer-only/future. Make local IPC limitations explicit, add future
hardening options, package the final DMG after inner stapling, and record the
GitHub Actions trust decision in public release docs plus planning notes.

</specifics>

<deferred>
## Deferred Ideas

- Full SHA pinning of all critical GitHub Actions is deferred unless the project
  decides to move release publication/signing deeper into CI.
- PKG-primary installer UX is deferred until Developer ID Installer signing and
  validation are complete.
- Live Apple notarization evidence remains Phase 16 validation work.

</deferred>
