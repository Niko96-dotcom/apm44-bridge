# Phase 14 Code Review: Release Automation Fail-Closed

**Reviewed:** 2026-06-12
**Status:** Clean after follow-up fix
**Reviewer:** Codex manual review

## Scope Reviewed

- `scripts/notary-result.sh`
- `scripts/notarize-release-dmg.sh`
- `scripts/notarize-release-pkg.sh`
- `scripts/release-all.sh`
- `tests/test_release_scripts.sh`
- `scripts/ci.sh`
- `.github/workflows/sign-notarize.yml`
- `.planning/phases/14-release-automation-fail-closed/14-01-SUMMARY.md`
- `.planning/phases/14-release-automation-fail-closed/14-02-SUMMARY.md`

## Findings

No open findings.

## Fixes Made During Review

- Replaced `head -1` based notary submission-id extraction with a single `sed`
  parser that quits after the first id without depending on a potentially
  pipefail-sensitive downstream command.
- Reworked PKG installer identity discovery to capture `security` output first,
  then select the first matching Developer ID Installer identity without a
  `security | sed | head` pipeline.

## Verification Evidence

```bash
bash -n scripts/notary-result.sh scripts/notarize-release-pkg.sh tests/test_release_scripts.sh
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Results:
- Release script matrix passed.
- Full CI passed after the final code commits.
- `scripts/ci.sh` proof included secret scan, native build/tests, release-script
  tests, Swift app build, Swift unit tests, app helper embedding, and
  installed-sync dry-run with matching repo/helper build ids.

## Tool Gaps

- `shellcheck` is not installed in this environment, so static shell linting was
  not available. Bash syntax checks and the mocked regression matrix were run
  instead.

## Residual Risk

- Live Apple notarization was not attempted because it requires maintainer
  credentials and external Apple service availability. Phase 16 should record
  that live validation or exact unblock commands.
