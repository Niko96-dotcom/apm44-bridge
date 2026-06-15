# Installing APM44 Bridge (end users)

APM44 Bridge is a **macOS menu bar app** plus a **HAL audio driver**. Producers run Cubase (or another DAW) at **44.1 kHz** into **APM44 Bridge**, and hear monitoring on **AirPods Max USB-C at 48 kHz**.

## What you download

From [GitHub Releases](https://github.com/Niko96-dotcom/apm44-bridge/releases):

| Artifact | Use when |
|----------|----------|
| **`APM44Bridge-0.10.0.dmg`** | Current DMG-primary public release artifact; run **Install APM44 Bridge.command** inside the DMG |
| **`APM44Bridge-0.10.0.dmg.sha256`** | Optional checksum file for verifying the download before opening the DMG |

Maintainer build: `bash scripts/release-all.sh` produces the signed,
notarized, stapled DMG. The final DMG is packaged after the inner app and HAL
driver are stapled and validated. The PKG flow is maintainer-only until
Developer ID Installer signing, installer UX, and validation are complete.

If you clone the repository instead of downloading a release, treat that as a
developer build path. You can run `bash scripts/ci.sh` to build and test the
project, but a reliable HAL install for normal use should come from the signed,
notarized DMG release.

## Install

1. Download the latest `APM44Bridge-<version>.dmg` release artifact from the release page.
2. Optional: download the matching `.sha256` file and verify the DMG:

   ```bash
   shasum -a 256 -c APM44Bridge-<version>.dmg.sha256
   ```

3. Open the DMG and run **Install APM44 Bridge.command**.
4. Enter your Mac admin password in Terminal when asked. This is expected:
   APM44 Bridge installs a HAL audio driver under
   `/Library/Audio/Plug-Ins/HAL/`, which macOS protects as an admin location.
5. **Reboot once** if **APM44 Bridge** does not appear in **Audio MIDI Setup** (first HAL install).

## Verify installation

After the installer finishes:

1. Open **Applications** and confirm **APM44 Bridge.app** is present.
2. Open **Audio MIDI Setup** and confirm **APM44 Bridge** appears as an audio device.
3. Optional Terminal check:

   ```bash
   test -d "/Applications/APM44 Bridge.app" && echo "app installed"
   test -d "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver" && echo "driver installed"
   ```

## After install — every session

1. Plug **AirPods Max via USB-C** (not Bluetooth-only for best stability).
2. Open **Audio MIDI Setup**:
   - **APM44 Bridge** → **44.1 kHz**
   - **AirPods** (USB) → **48.0 kHz**
3. Launch **APM44 Bridge** from **Applications** (or add it to **Login Items** so it starts at login).
4. Click the **headphones** icon in the menu bar (check the `…` overflow if the bar is crowded).
5. Choose **AirPods** output → **Start**.
6. In **Cubase**: Studio Setup → driver **APM44 Bridge** @ 44.1 kHz; Control Room Monitor L/R → **APM44 Bridge**.

Full Cubase steps: [first-run-cubase.md](first-run-cubase.md).

## No Dock icon?

The app is **menu bar only** (by design). It does not appear in the Dock. Use the **headphones** menu bar icon.

## Latency / clicks

In the menu bar panel:

- **Safe (~30 ms)** + highest SRC quality — fresh-install default; best for long sessions and subtle click-free monitoring.
- **Balanced** — lower-latency everyday option after setup; HAL path uses at least ~20 ms internal buffer automatically.
- **Low** — lowest latency; may click if the DAW or Bluetooth adds jitter.

If you hear rare tiny clicks, switch to **Safe**, use **USB-C** AirPods, and
watch **Hard xruns** and **Recoveries** in the menu bar while playing.

## Uninstall

```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo killall coreaudiod
rm -rf "/Applications/APM44 Bridge.app"
```

## Requirements

- macOS **14.0** or later
- Apple Silicon or Intel Mac
- Signed/notarized build (Developer ID) for reliable HAL load on macOS 15+
