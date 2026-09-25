# APM44 Bridge

[![CI](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/ci.yml)
[![Secret Scan](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/secret-scan.yml)
[![CodeQL](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/codeql.yml/badge.svg)](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

APM44 Bridge is for producers who track and mix at 44.1 kHz but monitor on
AirPods Max connected over USB-C, which run at 48 kHz. It presents a virtual
44.1 kHz Core Audio output device to the DAW and resamples to the headphones in
user space, so the session rate never has to change.

## Download

Download the latest release (signed, notarized DMG containing a signed PKG):
[GitHub Releases](https://github.com/Niko96-dotcom/apm44-bridge/releases/latest).

Requirements: macOS 14 or newer, Apple silicon or Intel Mac, AirPods Max over
USB-C. See the [end-user install guide](docs/install.md).

## Features

- A virtual 44.1 kHz output device, **APM44 Bridge**, that any DAW can select.
- High-quality resampling to 48 kHz (libsamplerate) with automatic clock-drift correction.
- Picks your USB-C AirPods Max automatically and lists other compatible 48 kHz outputs.
- **Buffering** presets (Low, Balanced, Safe) and resampling **Quality** (Standard, High, Best).
- Lives in the menu bar, with Start/Stop, Open at login and guided Setup.
- Updates itself: checks at launch, or on demand with **Check for Updates…**; app and driver always update together.
- Clear guidance when the audio driver needs a reload or reinstall.

## Quick start

1. Open the DMG from the [latest release](https://github.com/Niko96-dotcom/apm44-bridge/releases/latest) and run the installer. It installs the app and its audio driver, then opens the app.
2. In the DAW, select **APM44 Bridge** as the audio output. In Cubase, assign Control Room Monitor L/R to **APM44 Bridge** — see the [Cubase first-run guide](docs/first-run-cubase.md).
3. In the menu-bar app, pick the AirPods output and press **Start**.

## How it works

```text
Cubase 15 / DAW at 44.1 kHz
  -> APM44 Bridge HAL output device at 44.1 kHz
  -> apm44-bridge user-space daemon
  -> AirPods Max USB-C at 48 kHz
```

The headphones are not retuned to 44.1 kHz. APM44 Bridge presents a virtual
44.1 kHz Core Audio output device upstream, resamples in user space, handles
clock drift, and plays to the physical 48 kHz endpoint.

Tested with Cubase 15. Logic Pro and Ableton Live are not yet validated — see
the [DAW validation matrix](docs/daw-matrix.md).

## Status

| Component | Status |
|-----------|--------|
| HAL driver `APM44Bridge.driver` | 44.1 kHz virtual output device |
| Bridge daemon `apm44-bridge` | libsamplerate conversion and drift control |
| Menu bar app `APM44 Bridge` | virtual-device mode, latency presets, first-run checks, visible Quit control |
| Release packaging | Developer ID signed PKG inside signed/notarized DMG |

## Development

Requirements:

- macOS 14 or newer
- Xcode 16.x, or Xcode 15.4+
- CMake 3.28+
- XcodeGen (`brew install cmake xcodegen`)

```bash
git clone --recurse-submodules https://github.com/Niko96-dotcom/apm44-bridge.git
cd apm44-bridge
bash scripts/ci.sh
```

Useful focused checks:

```bash
bash scripts/check-secrets.sh
bash scripts/verify-app-build.sh
bash scripts/rebuild-and-open-app.sh
bash scripts/verify-menu-bar.sh
bash scripts/ci-soak.sh
```

For a local UI instance with separate preferences that leaves the installed
app running, use `bash scripts/rebuild-and-open-app.sh --isolated`.
See [local verification and performance](docs/development-verification.md) for
its audio-device limits, repeatable measurements, worktree setup, and the
Xcode compiler-probe workaround if a build stalls during discovery.

Hardware pre-flight checks (default `--hal`: APM44 Bridge @ 44100 + AirPods @ 48000; BlackHole not required):

```bash
bash scripts/verify-devices.sh --hal
bash scripts/verify-devices.sh --fallback  # legacy BlackHole route only
bash scripts/verify-hal-driver.sh
```

## Release

End users should install the signed, notarized DMG from GitHub Releases. Source
builds are useful for development, but a reliable public HAL install on modern
macOS requires Developer ID signing and notarization.

On a maintainer Mac with Developer ID Application and Installer certificates
plus a configured notarytool profile, build the public PKG-in-DMG release with:

```bash
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export INSTALLER_SIGN_ID="Developer ID Installer: Your Name (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
bash scripts/release-all.sh
```

See [docs/release.md](docs/release.md) for manual signing, notarization,
stapling, and troubleshooting steps.

## Documentation

| Doc | Purpose |
|-----|---------|
| [install.md](docs/install.md) | End-user install and daily use |
| [first-run-cubase.md](docs/first-run-cubase.md) | Cubase 15 Control Room setup |
| [cubase-soak.md](docs/cubase-soak.md) | 30+ minute QA soak |
| [daw-matrix.md](docs/daw-matrix.md) | DAW validation matrix |
| [release.md](docs/release.md) | Signing and notarization |
| [hal-driver.md](docs/hal-driver.md) | HAL driver and shared memory IPC |
| [menu-bar-app.md](docs/menu-bar-app.md) | Menu bar app architecture |
| [mvp-routing.md](docs/mvp-routing.md) | BlackHole fallback path |

## BlackHole Fallback

The fallback route is:

```text
DAW -> BlackHole 2ch at 44.1 kHz -> apm44-bridge -> AirPods at 48 kHz
```

BlackHole is optional, external, and not bundled. See
[docs/blackhole-prerequisite.md](docs/blackhole-prerequisite.md).

## Security

Please report suspected vulnerabilities privately. See [SECURITY.md](SECURITY.md).

## License

APM44 Bridge is open source under the [MIT License](LICENSE). Third-party
notices are in [NOTICE](NOTICE) and [third_party/README.md](third_party/README.md).
