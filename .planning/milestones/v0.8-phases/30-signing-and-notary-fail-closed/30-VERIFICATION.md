---
phase: 30-signing-and-notary-fail-closed
status: passed
verified: 2026-06-13
score: 5/5
human_verification_required: false
---

# Phase 30 Verification: Signing and Notary Fail-Closed

## Verdict

Phase 30 passed automated verification.

## Must-Haves

| # | Must-have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `sign-notarize.yml` builds both `apm44-bridge` and `APM44Bridge`. | Passed | Workflow contains `cmake --build build --target apm44-bridge APM44Bridge`. |
| 2 | Missing `APPLE_SIGN_ID` fails the workflow. | Passed | Signing step emits `error: APPLE_SIGN_ID secret is required for manual release signing` and exits 1. |
| 3 | Missing `AC_NOTARY` fails when `notarize=true`. | Passed | Notarize step emits `error: AC_NOTARY keychain profile is required when notarize=true` and exits 1. |
| 4 | HAL driver notarization uses shared strict accepted-status handling. | Passed | `scripts/notarize-hal-driver.sh` sources `scripts/notary-result.sh` and calls `require_notary_accepted`. |
| 5 | Release-script regression tests catch workflow/notary drift. | Passed | `bash tests/test_release_scripts.sh` passed. |

## Automated Checks

```bash
bash tests/test_release_scripts.sh
```

Result: passed.

## Human Verification

None required.

## Gaps

None.
