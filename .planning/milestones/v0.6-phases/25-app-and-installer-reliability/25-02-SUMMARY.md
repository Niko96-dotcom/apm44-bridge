---
phase: 25-app-and-installer-reliability
plan: 02
subsystem: release-scripts
tags: [dmg, installer, release-tests]
provides:
  - Deterministic DMG command app bundle replacement
  - Release-script regression guard for DIST-05
key-files:
  created:
    - .planning/phases/25-app-and-installer-reliability/25-02-SUMMARY.md
  modified:
    - scripts/build-release-dmg.sh
    - tests/test_release_scripts.sh
requirements-completed: [DIST-05]
completed: 2026-06-13
---

# Phase 25 Plan 02 Summary: Deterministic DMG App Install

## Accomplishments

- Updated the generated DMG command installer to remove `/Applications/APM44 Bridge.app` before copying.
- Replaced plain `cp -R` with privileged `sudo ditto`.
- Added `sudo chown -R root:wheel` for the installed app bundle.
- Added `DIST-05` coverage to `tests/test_release_scripts.sh`.

## Verification

```bash
bash tests/test_release_scripts.sh
```

Result: passed.
