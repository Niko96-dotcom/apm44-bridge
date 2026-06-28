# Architecture Research

**Domain:** Open-source macOS audio utility release hygiene
**Researched:** 2026-06-28
**Confidence:** HIGH

## Standard Architecture

APM44 Bridge should keep release confidence as a layered system:

```text
User-facing app
  - Menu/status UI
  - Quit action
  - BridgeProcessManager lifecycle

Audio runtime
  - User-space daemon
  - HAL driver
  - Shared-memory ring

Release evidence
  - CI and source-audit tests
  - Installed app/helper/driver identity checks
  - Signing, notarization, stapling, Gatekeeper checks
  - GitHub release metadata and artifacts

Public surface
  - README, docs, license, SECURITY, CONTRIBUTING
  - Issue templates and repo metadata
  - Release notes and checksums
```

## Component Responsibilities

| Component | Responsibility | v1.1 Impact |
|-----------|----------------|-------------|
| App menu/UI | Expose a clear user exit path | Add Quit control without new framework. |
| BridgeProcessManager | Stop app-owned bridge process cleanly | Reuse existing stop/idle transition logic. |
| HAL driver | Remain installed and safe | Quit must not uninstall or mutate privileged driver state. |
| Release scripts | Produce and verify public artifacts | Fail closed on missing signing/notary/artifact checks. |
| Docs/public repo | Tell the exact current truth | Align release names, caveats, install/uninstall, support, and security posture. |
| GitHub release | Public artifact of record | Publish/verify latest release only after gates pass. |

## Architectural Patterns

### Pattern 1: UI command delegates to lifecycle owner

The Quit action should call the app's existing lifecycle/stop path, then
terminate the app. It should not duplicate daemon-kill logic in the UI layer.

### Pattern 2: Release gate before publication

Publication is the last step. All evidence should be collected before upload:
working tree review, tests, secret scan, docs, artifact signing/notary checks,
installed sync, and known caveats.

### Pattern 3: Public truth over broad claims

Docs should state what is validated, what is future scope, and what remains
operator-dependent. That is safer than overclaiming compatibility or release
completeness.

## Integration Points

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Menu UI to process manager | Swift method call | Quit should route through existing stop semantics. |
| App bundle to helper | Embedded daemon build ID | Verify with existing app embed and installed-sync gates. |
| Helper to HAL driver | Shared-memory build ID/sample rate | Verify with `--shm-status` and HAL driver scripts. |
| Local release to GitHub | `gh release` | Verify latest release and assets after upload. |
| Public docs to artifact names | Documentation references | Prevent stale version/path/default claims. |

## Sources

- GitHub Docs: releases, repository profile files, secret scanning.
- Apple Developer Documentation: notarization and Gatekeeper distribution model.
- Local APM44 Bridge planning and release validation history.

---
*Architecture research for: APM44 Bridge v1.1*
*Researched: 2026-06-28*
