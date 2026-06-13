# APM44 Bridge

[![CI](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/ci.yml)
[![Secret Scan](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/secret-scan.yml)
[![CodeQL](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/codeql.yml/badge.svg)](https://github.com/Niko96-dotcom/apm44-bridge/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

APM44 Bridge is a macOS audio bridge for producers who want to keep DAW
sessions at **44.1 kHz** while monitoring through **AirPods Max USB-C at
48 kHz**.

Production path:

```text
DAW / Cubase / Logic / Ableton
  -> APM44 Bridge HAL output device at 44.1 kHz
  -> apm44-bridge user-space daemon
  -> AirPods Max USB-C at 48 kHz
```

The headphones are not retuned to 44.1 kHz. APM44 Bridge presents a virtual
44.1 kHz Core Audio output device upstream, resamples in user space, handles
clock drift, and plays to the physical 48 kHz endpoint.

## Status

| Component | Status |
|-----------|--------|
| HAL driver `APM44Bridge.driver` | 44.1 kHz virtual output device |
| Bridge daemon `apm44-bridge` | libsamplerate conversion and drift control |
| Menu bar app `APM44 Bridge` | virtual-device mode, latency presets, first-run checks |
| Release packaging | Developer ID signing, DMG-primary public release, maintainer-only PKG scripts |

## Install

Download the latest DMG-primary release from
[GitHub Releases](https://github.com/Niko96-dotcom/apm44-bridge/releases).

Start with:

- [End-user install guide](docs/install.md)
- [Cubase first-run guide](docs/first-run-cubase.md)
- [30+ minute soak checklist](docs/cubase-soak.md)

## Development

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

Hardware pre-flight checks:

```bash
bash scripts/verify-devices.sh
bash scripts/verify-hal-driver.sh
```

## Release

On a maintainer Mac with Developer ID certificates and a configured notarytool
profile:

```bash
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
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
