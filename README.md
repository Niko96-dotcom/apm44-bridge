# APM44 Bridge

macOS audio bridge: DAW sessions stay at **44.1 kHz** while monitoring through **AirPods Max USB-C at 48 kHz**.

**Production path:** Cubase/DAW → **APM44 Bridge** (HAL virtual device) → `apm44-bridge` → **AirPods @ 48 kHz**.

| Component | Status |
|-----------|--------|
| HAL driver `APM44Bridge.driver` | ✓ 44.1 kHz only, signed + notarized |
| Bridge daemon `apm44-bridge` | ✓ libsamplerate + drift controller |
| Menu bar app **APM44 Bridge** | ✓ `--virtual-device`, latency presets, open at login |
| Release pkg/DMG | ✓ `scripts/build-release-pkg.sh` |

## Install (end users)

Download **`APM44Bridge-0.1.0.pkg`** from [GitHub Releases](https://github.com/Niko96-dotcom/apm44-bridge/releases), double-click, enter your password, reboot once if the device is missing in Audio MIDI Setup.

Then every session: open **APM44 Bridge** from Applications → menu bar **headphones** icon → **Start** → play in Cubase.

Full guide: **[docs/install.md](docs/install.md)** · Cubase: **[docs/first-run-cubase.md](docs/first-run-cubase.md)**

## Maintainer release (signed + notarized)

On a Mac with **Developer ID Application**, **Developer ID Installer**, and **`AC_NOTARY`** profile:

```bash
bash scripts/release-all.sh
```

Artifacts: `build/signing/APM44Bridge-0.1.0.pkg`, `build/signing/APM44Bridge-0.1.0.dmg`

See **[docs/release.md](docs/release.md)** for manual steps.

## Developer build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
(cd App && xcodegen generate)
bash scripts/verify-app-build.sh
bash scripts/embed-daemon-in-app.sh
```

Pre-flight:

```bash
bash scripts/verify-devices.sh
bash scripts/verify-hal-driver.sh
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [install.md](docs/install.md) | End-user install & daily use |
| [first-run-cubase.md](docs/first-run-cubase.md) | Cubase 15 Control Room |
| [cubase-soak.md](docs/cubase-soak.md) | 30+ min QA soak |
| [release.md](docs/release.md) | Signing & notarization |
| [hal-driver.md](docs/hal-driver.md) | HAL + shm IPC |
| [menu-bar-app.md](docs/menu-bar-app.md) | App architecture |
| [mvp-routing.md](docs/mvp-routing.md) | BlackHole fallback path |

## MVP fallback (BlackHole)

DAW → **BlackHole 2ch @ 44100** → `apm44-bridge` → AirPods. Used when HAL is not installed. [BlackHole](https://github.com/ExistentialAudio/BlackHole/releases) is GPL-3.0 — not bundled.

## License

See repository license. HAL/driver and application are proprietary unless otherwise noted.
