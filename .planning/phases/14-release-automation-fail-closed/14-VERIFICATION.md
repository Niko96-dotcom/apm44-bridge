# Phase 14 Verification: Release Automation Fail-Closed

**Verified:** 2026-06-12
**Status:** Passed

## Scope

Phase 14 verified release automation fail-closed behavior for:

- strict DMG/PKG notarization status parsing,
- notary failure output/log preservation,
- `release-all.sh` missing-credential failure,
- explicit local-only unnotarized override labeling,
- signing workflow app-build strictness,
- credential-free release-script regression coverage, and
- CI wiring for release-script tests plus embedded-helper sync.

## Automated Evidence

```bash
gsd-sdk query verify.schema-drift 14
```

Result: no drift detected; blocking false.

```bash
gsd-sdk query verify.codebase-drift
```

Result: skipped with `no-structure-md`; action required false.

```bash
bash tests/test_release_scripts.sh
```

Result: passed. The matrix covered accepted, rejected, auth-failure,
network-failure, malformed notary output, release-all missing credentials, and
the explicit unnotarized override.

```bash
bash scripts/ci.sh
```

Result: passed.

CI evidence included:
- secret scan: OK, 1147 tracked/non-ignored files scanned,
- native build and all native tests,
- release-script regression tests,
- Swift app build,
- Swift unit tests: 42 tests passed,
- app helper embedding, and
- installed-sync dry-run with matching repo/helper build id
  `0.1.1+340e9f0dff59`.

## Manual Review Evidence

`14-REVIEW.md` status: clean after follow-up fix.

Review follow-up fixed pipefail-prone parsing in:

- `scripts/notary-result.sh`,
- `scripts/notarize-release-pkg.sh`.

## Tool Gaps

`shellcheck` is not installed in this environment, so static shell linting was
not run. Bash syntax checks, mocked release-script regression tests, source
review, and full CI were run instead.

## Residual Risk

Live Apple notarization was not attempted because it requires maintainer
credentials and Apple service availability. Phase 16 should either record live
notarization/stapling/Gatekeeper evidence or exact unblock commands.
