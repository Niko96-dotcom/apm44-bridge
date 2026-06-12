# Phase 15 Code Review: Public Distribution UX and Security Posture

**Reviewed:** 2026-06-12
**Status:** Clean after follow-up fix
**Reviewer:** Codex manual review

## Scope Reviewed

- `docs/hal-driver.md`
- `docs/install.md`
- `docs/release.md`
- `README.md`
- `scripts/build-release-dmg.sh`
- `scripts/release-all.sh`
- `scripts/notary-dry-run.sh`
- `tests/test_release_scripts.sh`
- `.github/workflows/release.yml`
- `.github/workflows/sign-notarize.yml`
- `.planning/PROJECT.md`
- `.planning/phases/15-public-distribution-ux-and-security-posture/15-01-SUMMARY.md`
- `.planning/phases/15-public-distribution-ux-and-security-posture/15-02-SUMMARY.md`

## Findings

No open findings.

## Fixes Made During Review

- Updated `scripts/notary-dry-run.sh` to use the shared
  `require_notary_accepted` helper so `release-all.sh` does not staple inner
  artifacts after a malformed or non-accepted app/driver evidence zip result.
- Updated the 15-02 summary to record that fail-closed dry-run notarization
  behavior.

## Verification Evidence

```bash
bash -n scripts/notary-dry-run.sh scripts/notary-result.sh scripts/build-release-dmg.sh scripts/release-all.sh tests/test_release_scripts.sh
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Results:
- Release script matrix passed.
- Full CI passed after the final Phase 15 code commits.
- `scripts/ci.sh` proof included secret scan, native build/tests,
  release-script tests, Swift app build, Swift unit tests, app helper embedding,
  and installed-sync dry-run with matching repo/helper build id
  `0.1.1+b9d2a36dc730`.

## Tool Gaps

- `shellcheck` is not installed in this environment, so static shell linting was
  not available. Bash syntax checks, source review, the mocked release-script
  matrix, and full CI were run instead.

## Residual Risk

- The explicit GitHub Actions trust decision defers full-length SHA pinning by
  design. If signing/notarization/publication moves further into GitHub-hosted
  automation, full SHA pinning should be implemented before that release path is
  trusted.
- Live Apple notarization, stapling, and Gatekeeper assessment remain Phase 16
  validation work because they require maintainer credentials and external
  Apple service availability.
