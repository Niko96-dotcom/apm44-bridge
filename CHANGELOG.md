# Changelog

All notable user-facing changes will be documented here.

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
