# Changelog

All notable user-facing changes will be documented here.

## 0.12.7 - 2026-09-05

- Reduced shared-memory audio transfer overhead by copying contiguous ring
  spans instead of calculating wraparound for every frame. Audio quality,
  buffering settings, and validation are unchanged.
- Added repeatable transfer benchmarks and stronger tests for stereo ordering,
  wraparound, and partial transfers.
- Added an isolated development app launch and fixed verification with custom
  build directories and fresh worktrees.
- Added an opt-in workaround for Xcode 26.6 compiler discovery stalls, preserving
  compiler diagnostics and failure reporting.

## 0.12.6 - 2026-09-05

- Fixed discovery of USB AirPods Max that macOS lists before activating their
  audio device. Starting the bridge now activates the selected USB output.
- Cleared reconnect notices when the connection recovers and made the signal
  path show the selected output device.
- Fixed validation of 44.1 kHz DAW exports with current macOS audio metadata.
- Simplified process management and audio internals, removed redundant tests,
  and corrected ordering when publishing audio metrics between threads.

## 0.12.5 - 2026-08-01

- Made sanitizer CI use complete Git history so native version metadata is
  deterministic on every runner.
- Made hosted public-release verification enforce the signed appcast
  cryptographically.

## 0.12.4 - 2026-08-01

- Corrected the Sparkle no-update result so a current installation returns to
  the quiet menu-bar state instead of showing a failure message.
- Avoided the launch-time update-session race that could leave the updater
  stuck on “Checking…” while the app was already current.
- Embedded the signed Markdown release notes in the HTTPS appcast so
  `SURequireSignedFeed` verifies the complete update presentation.

## 0.12.3 - 2026-08-01

- Added a signed Sparkle 2 in-app updater with musician-facing update status,
  release notes, administrator authorization, and safe relaunch handling.
- Published package updates replace the menu-bar app and HAL driver together,
  reload Core Audio, and verify matching app/driver/helper build identities.
- Added signed appcast generation and immutable GitHub Release publication
  gates for the notarized PKG update path.

## 0.12.2 - 2026-08-01

- Promoted the installed AirPods Max playback path to the release source of
  truth, including burst-safe buffering and recovery diagnostics for long
  callbacks.
- Added a fallback controls window and device refresh on every visible control
  surface, so reopening the menu-bar app restores usable output selection.
- Safe latency now uses a 100 ms target to keep burst-oriented output devices
  away from the edge during extended monitoring sessions.

## 0.12.1 - 2026-07-01

- Fixed the menu bar app reporting version **0.11.1** inside the 0.12.x
  releases; it now reports its real version.
- First-run setup now tells the truth about the driver. It distinguishes
  **installed but not loaded yet** (the driver is on disk and macOS needs a
  one-time restart or Core Audio reload — with a one-click **Reload audio
  driver** button) from **not installed** (re-run the installer), instead of
  pointing new users at a developer script they do not have.
- The installer now reloads Core Audio more reliably after a first-time driver
  install and waits for the virtual device to enumerate before opening the app,
  so the setup screen no longer briefly claims the driver is missing.

## 0.12.0 - 2026-07-01

- Promoted the public installer to a Developer ID Installer-signed **PKG inside
  a signed, notarized, stapled DMG**. Install by opening the DMG and running
  `APM44Bridge-<version>.pkg`; the direct PKG, checksums, and package provenance
  are attached for verification.

## 0.11.1 - 2026-07-01

- Updated the menu bar app icon to the new AirPods Max point-cloud artwork.

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
