# 14-02 Summary: Signing Workflow and Release-Script Regression Tests

**Completed:** 2026-06-12
**Status:** Complete

## Work Completed

- Removed the `|| true` soft-fail from
  `.github/workflows/sign-notarize.yml` so app build verification failures stop
  the signing workflow.
- Added `tests/test_release_scripts.sh`, a credential-free shell regression
  matrix with fake `xcrun`, `security`, `xcodegen`, and release child-command
  shims.
- Covered accepted, rejected, auth-failure, network-failure, and malformed
  `notarytool` submit output.
- Covered both DMG and PKG accepted/rejected notarization paths.
- Covered `release-all.sh` missing notary credentials and the explicit
  `APM44_ALLOW_UNNOTARIZED=1` local-only override.
- Wired `tests/test_release_scripts.sh` into `scripts/ci.sh`.
- Added a CI embed step before `verify-installed-sync.sh --dry-run` when a
  repo-local app bundle exists, preventing stale embedded helpers from
  masquerading as current release automation state.

## Requirements Closed

- REL-06: The signing workflow no longer masks app build verification failure.
- REL-07: Release-script regression coverage simulates accepted, rejected,
  auth-failure, network-failure, and malformed `notarytool` output without
  Apple credentials.

## Verification

```bash
bash -n tests/test_release_scripts.sh scripts/ci.sh
bash tests/test_release_scripts.sh
grep -n 'bash scripts/verify-app-build.sh' .github/workflows/sign-notarize.yml
grep -n 'test_release_scripts.sh\|Embed daemon in app bundle\|APM44_BUILD_CONFIG' scripts/ci.sh
bash scripts/ci.sh
```

All checks passed. The full CI run completed secret scan, native build/tests,
release-script tests, Swift app build, Swift unit tests, app helper embedding,
and installed-sync dry-run.

## Follow-Up

Phase 14 still needs phase-level code review and verification closure. Live
Apple notarization remains a Phase 16 maintainer-credential validation item.
