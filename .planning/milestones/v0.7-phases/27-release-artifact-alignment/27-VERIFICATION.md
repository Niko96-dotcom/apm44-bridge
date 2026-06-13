---
phase: 27-release-artifact-alignment
status: passed
verified: 2026-06-13
score: 5/5
human_verification_required: false
---

# Phase 27 Verification: Release Artifact Alignment

## Verdict

Phase 27 passed automated verification.

## Must-Haves

| # | Must-have | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `sign-notarize.yml` builds the app with `xcodebuild -configuration Release`. | Passed | Workflow Build Release step now invokes `xcodebuild ... -configuration Release`. |
| 2 | Signing workflow writes `APM44 Bridge.app` into `build/Release`. | Passed | Workflow sets `CONFIGURATION_BUILD_DIR="$PWD/build/Release"` and verifies with `APM44_APP_OUTPUT_DIR="$PWD/build/Release"`. |
| 3 | Signing workflow signs and verifies the same Release app artifact. | Passed | Signing step exports `APM44_APP_PATH` as `${{ github.workspace }}/build/Release/APM44 Bridge.app` before embed/sign/codesign verify. |
| 4 | `scripts/ci.sh` identifies a concrete app path before embed/installed-sync. | Passed | CI sets `APP_PATH="$BUILD_DIR/$CONFIG/APM44 Bridge.app"` and passes it to both scripts. |
| 5 | CI fails if the app bundle or embedded helper is missing. | Passed | CI checks `[[ -d "$APP_PATH" ]]` after app build and `[[ -x "$HELPER_PATH" ]]` after embed. |

## Automated Checks

```bash
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Results:

- `bash tests/test_release_scripts.sh`: passed.
- `bash scripts/ci.sh`: passed.
- Full CI evidence included Release app build to `/Users/niko/apm44-bridge/build/Release/APM44 Bridge.app`, embed, and installed-sync dry-run against that same path.

## Human Verification

None required.

## Gaps

None.
