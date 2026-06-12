# 15-02 Summary: Stapling Order and GitHub Actions Trust Posture

**Completed:** 2026-06-12
**Status:** Complete

## Work Completed

- Added `APM44_DMG_PACKAGE_ONLY=1` support to `scripts/build-release-dmg.sh` so
  the DMG can be packaged from existing app/driver artifacts without rebuilding
  or re-signing them.
- Updated `scripts/release-all.sh` to staple and validate the inner app and HAL
  driver before packaging the final public DMG.
- Updated `scripts/notary-dry-run.sh` to require accepted notary status for the
  app/driver evidence zip before `release-all.sh` staples inner artifacts.
- Updated `release-all.sh` to package that final DMG from the stapled inner
  artifacts before notarizing/stapling/validating the final container.
- Extended `tests/test_release_scripts.sh` to cover the notary-ready
  `release-all.sh` command sequence and prove package-only final DMG packaging
  is invoked.
- Updated `docs/release.md` and `docs/install.md` so docs and scripts agree on
  the final artifact order.
- Recorded the v0.4 GitHub Actions trust decision: official actions remain
  tag-pinned, Dependabot monitors weekly, and full-length SHA pinning is the
  future hardening trigger before moving more signing/notarization/publication
  into CI.
- Added release/signing workflow comments pointing to the documented trust
  decision.

## Requirements Closed

- PKG-03: Release automation staples and validates inner app/driver artifacts
  before packaging the final public DMG, then notarizes/staples/validates the
  final container.
- GHA-01: Critical release/signing workflow actions are covered by an explicit
  trust decision.

## Verification

```bash
bash -n scripts/build-release-dmg.sh scripts/release-all.sh tests/test_release_scripts.sh
bash tests/test_release_scripts.sh
grep -n 'APM44_DMG_PACKAGE_ONLY' scripts/build-release-dmg.sh scripts/release-all.sh
grep -n 'stapler validate "build/Release/APM44 Bridge.app"' scripts/release-all.sh
grep -n 'stapler validate build/Driver/APM44Bridge.driver' scripts/release-all.sh
grep -n 'GitHub Actions trust decision\|Dependabot\|full-length SHA\|trust decision' docs/release.md .planning/PROJECT.md .github/workflows/release.yml .github/workflows/sign-notarize.yml
```

All checks passed.

## Follow-Up

Phase 15 needs phase-level review and verification. Live Apple notarization and
Gatekeeper proof remain Phase 16 validation work.
