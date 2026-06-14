---
phase: 36-release-automation-and-workflow-intent
status: passed
score: 5/5
automated: true
completed: 2026-06-14
---

# Phase 36 Verification: Release Automation and Workflow Intent

## Must-Haves

| Check | Status | Evidence |
|-------|--------|----------|
| `release-all.sh` runs strict codesign verification before notarization | passed | `scripts/release-all.sh` runs `bash scripts/codesign-verify-release.sh` before `bash scripts/notary-dry-run.sh` |
| Regression coverage fails if the normal release path omits the gate | passed | `tests/test_release_scripts.sh` asserts the codesign verification log line exists and precedes the notary dry-run line |
| Local-development override remains explicit | passed | Existing `APM44_ALLOW_UNNOTARIZED=1` tests still pass and do not submit to notary service |
| `sign-notarize.yml` artifact intent is clear | passed | Workflow name/comments identify maintainer signing/notary evidence and no public DMG publication |
| Public workflow docs avoid overclaiming GitHub Actions authority | passed | `docs/release.md` says the workflow does not publish the public DMG unless upload is added later |

## Automated Checks

```bash
bash tests/test_release_scripts.sh
```

Result: passed.

## Human Verification

None required.
