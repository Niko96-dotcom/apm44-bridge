---
phase: 27-release-artifact-alignment
plan: 01
subsystem: signing-workflow
tags: [github-actions, release, signing, app-build]
provides:
  - Manual signing workflow Release app path alignment
  - Explicit app output directory support in verify-app-build.sh
key-files:
  created:
    - .planning/phases/27-release-artifact-alignment/27-01-SUMMARY.md
  modified:
    - .github/workflows/sign-notarize.yml
    - scripts/verify-app-build.sh
    - tests/test_release_scripts.sh
requirements-completed: [SIGN-01, SIGN-02, SIGN-03]
completed: 2026-06-13
---

# Phase 27 Plan 01 Summary: Signing Workflow Release Artifact Alignment

## Accomplishments

- Updated `.github/workflows/sign-notarize.yml` so the manual signing workflow builds the app with `xcodebuild -configuration Release`.
- Directed that workflow build to `CONFIGURATION_BUILD_DIR="$PWD/build/Release"`, matching the default app path consumed by release scripts.
- Passed `APM44_APP_PATH` into the signing step so embed, sign, and codesign verification inspect the same `build/Release/APM44 Bridge.app`.
- Extended `scripts/verify-app-build.sh` with `APM44_APP_OUTPUT_DIR` so local and workflow app-build proof can target the same Release output directory.
- Added release-script regression checks for SIGN-01 through SIGN-03.

## Verification

```bash
bash tests/test_release_scripts.sh
bash scripts/ci.sh
```

Result: passed.
