# Changelog

All notable user-facing changes will be documented here.

## Unreleased

- No user-facing changes since 0.11.0.

## 0.11.0 - 2026-06-30

- Added a visible **Quit APM44 Bridge** control to the menu bar app. Quit stops
  app-owned bridge work and exits the app without installing, uninstalling, or
  reloading the HAL driver.
- Hardened transient HAL restart handling and bounded shared-memory fill counts
  so impossible producer state cannot inflate reads.
- Tightened public release documentation around the v1.1 validation anchor:
  Cubase 15 with AirPods Max over USB-C.
- Regenerated the public DMG checksum after final DMG stapling so the uploaded
  checksum always matches the Gatekeeper-assessed artifact.
- Moved public release evidence toward `CHANGELOG.md` and
  `docs/release-validation.md`; local GSD planning history is kept out of the
  public release tree.

## 0.10.0 - 2026-06-15

- Published the current signed, notarized DMG path as the primary public
  install artifact.
- Hardened local app rebuilds so stale unsigned app bundles are removed before
  rebuilding, helpers are embedded before final signing, and the resulting app
  passes strict codesign verification.
- Kept GitHub release automation verification-only; public installable assets
  are built and notarized on a maintainer Mac before upload.
- Changed tag release automation to verification-only so CI no longer uploads
  unsigned installable app, driver, or daemon artifacts.
- Clarified public install, source-build, and legacy BlackHole fallback docs for
  open-source readers.

## 0.1.1 - 2026-06-03

- Fixed HAL virtual-device dropout recovery and virtual-source drift tracking.
- Clarified menu metrics by separating hard xruns from recoveries.
- Recorded Cubase 15 operator sign-off and 30+ minute soak completion.
- Made the public release path DMG-first; PKG tooling is maintainer-only until
  installer signing is fixed.
- Pruned internal planning files from the public repository.

## 0.1.0 - 2026-06-01

- Initial signed distribution path for APM44 Bridge.
- HAL virtual output device for 44.1 kHz DAW sessions.
- User-space bridge daemon with libsamplerate conversion and drift control.
- Swift menu bar app with virtual-device mode, latency presets, and first-run
  preflight checks.
- Release scripts for Developer ID signing, notarization, DMG, and PKG builds.
