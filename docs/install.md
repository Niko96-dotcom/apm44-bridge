# Installing APM44 Bridge (end users)

APM44 Bridge is a **macOS menu bar app** plus a **HAL audio driver**. The v1.2
validation anchor is Cubase 15 at **44.1 kHz** into **APM44 Bridge**, with
monitoring on **AirPods Max USB-C at 48 kHz**.

## What you download

From [GitHub Releases](https://github.com/Niko96-dotcom/apm44-bridge/releases):

| Artifact | Use when |
|----------|----------|
| **`APM44Bridge-0.12.5.dmg`** | Current PKG-in-DMG public release artifact; open **APM44Bridge-0.12.5.pkg** inside the DMG |
| **`APM44Bridge-0.12.5.dmg.sha256`** | Optional checksum file for verifying the download before opening the DMG |

Maintainer build: `bash scripts/release-all.sh` produces the signed,
notarized, stapled PKG-in-DMG release. The final DMG is packaged after the
inner app, HAL driver, and installer package are signed, notarized, stapled,
and validated.

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

3. Open the DMG and open **APM44Bridge-<version>.pkg**.
4. Enter your Mac admin password when Installer asks. This is expected:
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
7. To leave the app without changing the installed driver, use **Quit APM44
   Bridge** in the menu bar panel.

Full Cubase steps: [first-run-cubase.md](first-run-cubase.md).

## No Dock icon?

The app is **menu bar only** (by design). It does not appear in the Dock. Use the **headphones** menu bar icon.

Quit closes only the app and any app-owned bridge process. It does not uninstall
the HAL driver, reload Core Audio, or remove the virtual audio device.

## Latency / clicks

In the menu bar panel:

- **Safe (~100 ms)** + highest SRC quality — fresh-install default; best for long sessions and subtle click-free monitoring.
- **Balanced** — lower-latency everyday option after setup; HAL path uses at least ~20 ms internal buffer automatically.
- **Low** — lowest latency; may click if the DAW or Bluetooth adds jitter.

If you hear rare tiny clicks, switch to **Safe**, use **USB-C** AirPods, and
watch **Hard xruns** and **Recoveries** in the menu bar while playing.

## Uninstall

From a repository checkout, preview and run the uninstall helper:

```bash
bash scripts/uninstall-apm44.sh --dry-run
bash scripts/uninstall-apm44.sh --yes
```

Without a repository checkout, remove the installed app and HAL driver manually:

```bash
sudo rm -rf "/Applications/APM44 Bridge.app"
sudo rm -rf /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo pkgutil --forget com.niko.apm44.pkg 2>/dev/null || true
sudo killall coreaudiod 2>/dev/null || true
```

## Requirements

- macOS **14.0** or later
- Apple Silicon or Intel Mac
- Signed/notarized build (Developer ID) for reliable HAL load on macOS 15+
