---
phase: 25-app-and-installer-reliability
status: passed
verified: 2026-06-13
score: 5/5
human_verification_required: false
---

# Phase 25 Verification: App and Installer Reliability

## Verdict

Phase 25 passed automated verification.

## Must-Haves

| # | Must-have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `DeviceCatalog.refresh()` cannot block on unread helper stderr. | Passed | `DeviceCatalog.refresh` uses `FileHandle.nullDevice`; Swift guard test passed. |
| 2 | Bridge start resets `latestMetrics`, `lastMetricsAt`, and `metricsStale` together. | Passed | `testStartResetsMetricsStateAndTimestamp` passed. |
| 3 | Idle transition resets `latestMetrics`, `lastMetricsAt`, and `metricsStale` together. | Passed | `testIdleTransitionResetsMetricsStateAndTimestamp` passed. |
| 4 | Generated DMG command installer removes existing app, copies with privileged `ditto`, and sets root ownership. | Passed | `run_dist_05_dmg_command_installer_check` passed. |
| 5 | Swift and release-script regressions cover stderr, metrics reset, and installer command behavior. | Passed | Swift app suite and release-script tests passed. |

## Automated Checks

```bash
bash tests/test_release_scripts.sh
xcodebuild -project App/APM44Bridge.xcodeproj -scheme APM44Bridge -destination 'platform=macOS' -derivedDataPath build/app test -only-testing:APM44BridgeTests CODE_SIGNING_ALLOWED=NO
```

Results:

- Release script tests: passed.
- Swift app tests: passed, 46 tests.

## Human Verification

None required.

## Gaps

None.
