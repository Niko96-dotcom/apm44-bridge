---
title: APM44 Bridge
---

# APM44 Bridge

APM44 Bridge is for producers who track and mix at 44.1 kHz but monitor on
AirPods Max connected over USB-C, which run at 48 kHz. It presents a virtual
44.1 kHz Core Audio output device to the DAW and resamples to the headphones in
user space, so the session rate never has to change.

## Download

**[Download the latest release](https://github.com/Niko96-dotcom/apm44-bridge/releases/latest)**: a signed, notarized DMG containing the installer.

Requirements: macOS 14 or newer, Apple silicon or Intel Mac, AirPods Max over
USB-C.

## Quick start

1. Open the DMG and run the installer. It installs the app and its audio
   driver, then opens the app.
2. In the DAW, select **APM44 Bridge** as the audio output. In Cubase, assign
   Control Room Monitor L/R to **APM44 Bridge**.
3. In the menu-bar app, pick the AirPods output and press **Start**.

Full steps: [install guide](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/install.md)
and [Cubase first-run guide](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/first-run-cubase.md).

## Features

- A virtual 44.1 kHz output device, **APM44 Bridge**, that any DAW can select.
- High-quality resampling to 48 kHz (libsamplerate) with automatic clock-drift correction.
- Picks your USB-C AirPods Max automatically and lists other compatible 48 kHz outputs.
- **Buffering** presets (Low, Balanced, Safe) and resampling **Quality** (Standard, High, Best).
- Lives in the menu bar, with Start/Stop, Open at login and guided Setup.
- Updates itself: checks at launch, or on demand with **Check for Updates…**; app and driver always update together.
- Clear guidance when the audio driver needs a reload or reinstall.

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

Tested with Cubase 15. Logic Pro and Ableton Live are not yet validated.

## Guides

- [Install guide](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/install.md)
- [Cubase 15 first-run setup](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/first-run-cubase.md)
- [DAW validation matrix](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/daw-matrix.md)
- [30+ minute QA soak](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/cubase-soak.md)
- [Menu bar app](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/menu-bar-app.md)
- [HAL driver](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/hal-driver.md)

## Project links

- [Source code on GitHub](https://github.com/Niko96-dotcom/apm44-bridge)
- [Report an issue](https://github.com/Niko96-dotcom/apm44-bridge/issues)
- [MIT License](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/LICENSE)

BlackHole is an optional legacy fallback route, not required.
See the [BlackHole prerequisite](https://github.com/Niko96-dotcom/apm44-bridge/blob/main/docs/blackhole-prerequisite.md).
