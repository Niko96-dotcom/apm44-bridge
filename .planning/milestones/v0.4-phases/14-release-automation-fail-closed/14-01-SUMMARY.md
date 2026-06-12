# 14-01 Summary: Fail-Closed Notarization and Release-All

**Completed:** 2026-06-12
**Status:** Complete

## Work Completed

- Added `scripts/notary-result.sh` with shared `require_notary_accepted`
  handling for strict `notarytool submit` interpretation.
- Updated DMG and PKG notarization scripts to require both successful submit
  exit status and parsed `status: Accepted` before stapling.
- Preserved submit output on every notary path and added failure log fetching
  when a submission id is available.
- Changed `scripts/release-all.sh` so missing notary credentials fail by
  default.
- Added the explicit `APM44_ALLOW_UNNOTARIZED=1` local-only override and labelled
  override artifacts as unnotarized local-only builds.
- Removed the remaining soft-fail `|| true` pattern from release notary scripts.

## Requirements Closed

- REL-01: DMG notarization fails closed unless `notarytool` exits successfully
  and reports `status: Accepted`.
- REL-02: PKG notarization uses the same fail-closed contract.
- REL-03: Notary failure paths print submit output and fetch logs when possible.
- REL-04: `release-all.sh` treats missing notary credentials as release-blocking
  unless explicitly overridden.
- REL-05: Unnotarized override output is labelled local-only.

## Verification

```bash
bash -n scripts/notary-result.sh scripts/notarize-release-dmg.sh scripts/notarize-release-pkg.sh scripts/release-all.sh
if grep -n '|| true\|status: Invalid' scripts/notarize-release-dmg.sh scripts/notarize-release-pkg.sh; then exit 1; else echo 'no masked notary failure patterns'; fi
grep -n 'require_notary_accepted\|status:[[:space:]]*Accepted\|notarytool log' scripts/notary-result.sh scripts/notarize-release-dmg.sh scripts/notarize-release-pkg.sh
grep -n 'APM44_ALLOW_UNNOTARIZED\|local-only unnotarized\|exit 1' scripts/release-all.sh
```

All checks passed.

## Follow-Up

14-02 must add mocked release-script tests for accepted, rejected,
auth-failure, network-failure, malformed notary output, release-all missing
credentials, and the explicit local-only override. It must also remove the
signing workflow's masked app-build verification failure and wire the new test
runner into `scripts/ci.sh`.
