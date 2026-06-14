---
phase: 35-public-version-and-defaults-truth
status: passed
score: 4/4
automated: true
completed: 2026-06-14
---

# Phase 35 Verification: Public Version and Defaults Truth

## Must-Haves

| Check | Status | Evidence |
|-------|--------|----------|
| Public docs/templates use one current version identity | passed | Docs retain 0.1.1 app/artifact identity and release-validation now names v0.9 public-polish validation |
| Latency docs identify Safe as the fresh-install default | passed | `docs/install.md` and `docs/menu-bar-qa.md` updated; `run_doc_truth_check` guards the wording |
| Release docs reference `build/Driver/APM44Bridge.driver` | passed | `docs/release.md` updated; `run_doc_truth_check` rejects `build/Release/APM44Bridge.driver` |
| Source/script tests catch public-truth regressions | passed | `bash tests/test_release_scripts.sh` passed |

## Automated Checks

```bash
bash tests/test_release_scripts.sh
```

Result: passed.

## Human Verification

None required.
