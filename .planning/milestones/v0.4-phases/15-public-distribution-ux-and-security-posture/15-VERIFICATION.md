---
phase: 15-public-distribution-ux-and-security-posture
status: passed
verified: 2026-06-12
score: 5/5
human_verification_required: false
---

# Phase 15 Verification: Public Distribution UX and Security Posture

## Verdict

Phase 15 passed automated verification.

## Must-Haves

| # | Must-have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Public docs describe `/apm44_bridge_ring` as local IPC, not an authentication or privilege boundary. | Passed | `docs/hal-driver.md` and `docs/release.md` document the local-machine threat model, mode `0666`, no secrets/credentials/authz in the ring, and future hardening options. |
| 2 | Public install/release docs state the v0.4 distribution posture honestly. | Passed | `docs/install.md`, `docs/release.md`, and `README.md` describe DMG-primary public distribution, admin password rationale for HAL install, and PKG as maintainer-only/future until Developer ID Installer validation. |
| 3 | Final DMG packaging happens after inner app and driver stapling/validation in the notarization-ready release path. | Passed | `scripts/release-all.sh` validates the app and driver after stapling, then invokes `APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh` before DMG notarization. |
| 4 | GitHub Actions trust posture is documented and tracked. | Passed | `docs/release.md`, `.github/workflows/release.yml`, `.github/workflows/sign-notarize.yml`, and `.planning/PROJECT.md` record the tag-pinned official-action decision, Dependabot monitoring, and full-length SHA pinning trigger before expanding hosted signing/notarization/publication. |
| 5 | Phase 15 release-script changes are regression-tested and reviewed. | Passed | `tests/test_release_scripts.sh` covers package-only final DMG packaging and fail-closed dry-run notarization; `15-REVIEW.md` has no open findings after the shared notary-result helper fix. |

## Automated Checks

```bash
grep -n 'not an authentication or privilege boundary\|0666\|Future hardening' docs/hal-driver.md docs/release.md
grep -n 'DMG-primary\|maintainer-only\|admin password' docs/install.md docs/release.md README.md .planning/PROJECT.md
bash -n scripts/build-release-dmg.sh scripts/release-all.sh tests/test_release_scripts.sh
bash tests/test_release_scripts.sh
grep -n 'APM44_DMG_PACKAGE_ONLY' scripts/build-release-dmg.sh scripts/release-all.sh
grep -n 'stapler validate "build/Release/APM44 Bridge.app"' scripts/release-all.sh
grep -n 'stapler validate build/Driver/APM44Bridge.driver' scripts/release-all.sh
grep -n 'GitHub Actions trust decision\|Dependabot\|full-length SHA\|trust decision' docs/release.md .planning/PROJECT.md .github/workflows/release.yml .github/workflows/sign-notarize.yml
gsd-sdk query verify.schema-drift 15
gsd-sdk query verify.codebase-drift
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Results:

- IPC/security-posture documentation checks passed.
- DMG-primary and maintainer-only PKG documentation checks passed.
- Bash syntax checks passed for the touched release scripts and regression test.
- Release-script regression matrix passed.
- Schema drift check passed with no drift.
- Codebase drift check skipped with `no-structure-md`; action required false.
- Full CI passed after the final Phase 15 review commit.

CI evidence included:

- secret scan: OK, 1154 tracked/non-ignored files scanned,
- native build and all native tests,
- release-script regression tests,
- Swift app build,
- Swift unit tests: 42 tests passed,
- app helper embedding, and
- installed-sync dry-run with matching repo/helper build id
  `0.1.1+aea892215b06`.

## Manual Review Evidence

`15-REVIEW.md` status: clean after follow-up fix.

Review follow-up updated `scripts/notary-dry-run.sh` to call the shared
`require_notary_accepted` helper so malformed or non-accepted app/driver dry-run
notarization evidence cannot lead `release-all.sh` into stapling and packaging
inner artifacts.

## Tool Gaps

`shellcheck` is not installed in this environment, so static shell linting was
not run. Bash syntax checks, mocked release-script regression tests, source
review, and full CI were run instead.

## Residual Risk

Live Apple notarization, stapling, and Gatekeeper assessment were not attempted
in Phase 15 because they require maintainer credentials, Developer ID assets,
and Apple service availability. Phase 16 is explicitly scoped to record that
release validation evidence or exact unblock commands.

## Human Verification

None required for Phase 15. The remaining live release-validation work is Phase
16 scope.

## Gaps

None.
