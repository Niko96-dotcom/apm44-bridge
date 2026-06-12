# Release: code signing and notarization

Distribution checklist for **apm44-bridge**, **APM44 Bridge.app**, and **APM44Bridge.driver** (HAL Audio Server Plug-in).

## Prerequisites

- Apple Developer Program membership (required for HAL load on macOS 15+ in production)
- **Developer ID Application** certificate in Keychain
- Xcode 16.x (or 15.4+) with `codesign`, `xcrun notarytool`, `xcrun stapler`
- App-specific password or App Store Connect API key for notarization

## Artifacts

| Artifact | Path (typical) | Entitlements |
|----------|----------------|--------------|
| Bridge daemon | `build/BridgeDaemon/apm44-bridge` | none (CLI) |
| Menu bar app | `build/Release/APM44 Bridge.app` | `App/APM44Bridge/APM44Bridge.entitlements` |
| HAL plug-in | `build/Release/APM44Bridge.driver` | `Driver/APM44Bridge.entitlements` |

## Distribution posture

v0.4 is **DMG-primary** for public distribution. The public artifact is the
signed, notarized, stapled DMG produced by `scripts/release-all.sh`.

The DMG intentionally contains an admin installer command because the HAL driver
must be copied to `/Library/Audio/Plug-Ins/HAL/` and owned by `root:wheel`.
This is the supported public install path until a signed PKG installer becomes
the primary release artifact.

PKG tooling remains maintainer-only for now. Use `APM44_BUILD_PKG=1` only to
test the package path after Developer ID Installer signing and validation are
configured.

## Security / local IPC

`/apm44_bridge_ring` is local-machine IPC between the HAL producer and the
user-space daemon. It is not an authentication or privilege boundary.

The shm object currently uses mode **0666** so `coreaudiod` and the daemon can
open the same ring without a separate privileged broker. Other local processes
or users may be able to open the object while it exists. Do not place secrets,
credentials, account identifiers, or authorization decisions in the ring.

Current protection is limited to format/build integrity checks: ABI version,
object size, build id, and generation fields let the daemon reject stale or
malformed rings. These checks do not prevent another local process from opening
the shm object.

Future hardening options include per-user shm naming, tighter owner/group
permissions installed by a privileged helper, launchd-managed ring setup,
XPC-mediated coordination, or moving sensitive control state out of shared
memory.

Build Release binaries before signing:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
bash scripts/verify-app-build.sh   # generates Release .app when configured
```

## Developer ID signing (release)

Set your signing identity. If `SIGN_ID` is unset, `scripts/sign-release.sh`
auto-detects a single local Developer ID Application identity.

```bash
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="AC_NOTARY"
```

**One-command release** (build, sign, notarize, and staple the public DMG):

```bash
bash scripts/release-all.sh
```

The public artifact is `build/signing/APM44Bridge-<version>.dmg`.

Use [release-validation.md](release-validation.md) for the final automated
gate, artifact assessment commands, Gatekeeper assessment, and exact unblock
commands for Apple credential or hardware-dependent checks.

`release-all.sh` uses this order:

1. Build Release app, daemon, and driver.
2. Embed the current daemon into `APM44 Bridge.app`.
3. Sign the daemon, app, and driver.
4. Submit a signed app/driver evidence zip with `notarytool --wait`.
5. Staple and validate the inner app and driver.
6. Repackage the final DMG from those stapled inner artifacts.
7. Notarize, staple, and validate the final public DMG.

This order matters: the distributed DMG should contain the same stapled app and
driver that were validated immediately before the final container was created.

Manual steps (after Release build):

```bash
bash scripts/embed-daemon-in-app.sh
bash scripts/sign-release.sh
bash scripts/codesign-verify-release.sh
bash scripts/notary-dry-run.sh          # full zip submit (SHIP-02 evidence)
xcrun stapler staple "build/Release/APM44 Bridge.app"
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler staple build/Driver/APM44Bridge.driver
xcrun stapler validate build/Driver/APM44Bridge.driver
APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh
bash scripts/notarize-release-dmg.sh
# optional maintainer-only pkg:
APM44_BUILD_PKG=1 bash scripts/release-all.sh
# or driver-only:
bash scripts/notarize-hal-driver.sh
```

### Bridge daemon

```bash
codesign --force --sign "$SIGN_ID" \
  --timestamp --options runtime \
  build/BridgeDaemon/apm44-bridge
codesign --verify --verbose build/BridgeDaemon/apm44-bridge
```

### Menu bar app

Embed the daemon if your packaging copies it into `Contents/MacOS/` or `Resources/`, then sign inner binaries before the bundle:

```bash
APP="build/Release/APM44 Bridge.app"
codesign --force --sign "$SIGN_ID" \
  --timestamp --options runtime \
  --entitlements App/APM44Bridge/APM44Bridge.entitlements \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

### HAL driver

HAL plug-ins load inside `coreaudiod`. Use hardened runtime and the driver entitlements plist:

```bash
DRIVER="build/Release/APM44Bridge.driver"
codesign --force --sign "$SIGN_ID" \
  --timestamp --options runtime \
  --entitlements Driver/APM44Bridge.entitlements \
  "$DRIVER"
codesign --verify --deep --strict --verbose=2 "$DRIVER"
```

Install signed driver (requires admin):

```bash
sudo cp -R "$DRIVER" /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
bash scripts/reload-coreaudio.sh
# macOS 14.4+: launchctl kickstart for coreaudiod is blocked (SIP); uses sudo killall coreaudiod
```

For local development without a Developer ID cert, use `scripts/install-driver.sh` (ad-hoc sign).

## Notarization (dry-run / staging)

Apple expects a **container** (zip, dmg, or pkg), not loose binaries.

### 1. Package

Example zip of app + daemon:

```bash
RELEASE_DIR="$(mktemp -d)"
cp -R "build/Release/APM44 Bridge.app" "$RELEASE_DIR/"
cp build/BridgeDaemon/apm44-bridge "$RELEASE_DIR/"
ditto -c -k --keepParent "$RELEASE_DIR/APM44 Bridge.app" APM44Bridge-app.zip
```

For driver distribution, zip the signed `.driver` bundle separately or ship a pkg that installs to `/Library/Audio/Plug-Ins/HAL/`.

### 2. Submit

Using App Store Connect API key (recommended for CI):

```bash
xcrun notarytool submit APM44Bridge-app.zip \
  --keychain-profile "AC_NOTARY" \
  --wait
```

Using Apple ID (interactive / one-off):

```bash
xcrun notarytool submit APM44Bridge-app.zip \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait
```

Store credentials once:

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "<notarytool-password>"
```

### 3. Staple

After `status: Accepted`:

```bash
xcrun stapler staple "build/Release/APM44 Bridge.app"
xcrun stapler validate "build/Release/APM44 Bridge.app"
```

Re-zip if you ship a download artifact after stapling.

### 4. Log on failure

```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_NOTARY" notary-log.json
```

## Ad-hoc signing (local dev only)

Ad-hoc signed HAL bundles may fail AMFI on macOS 15+ before plug-in code runs. Use for **SIP-disabled / dev machines only**:

```bash
codesign --force --sign - --timestamp \
  --entitlements Driver/APM44Bridge.entitlements \
  build/Debug/APM44Bridge.driver
```

Or run:

```bash
bash scripts/install-driver.sh [path/to/APM44Bridge.driver]
```

## Entitlements notes

- **App** (`App/APM44Bridge/APM44Bridge.entitlements`): minimal; menu bar app spawns `apm44-bridge` subprocess. Add only entitlements required for hardened runtime (e.g. audio device access if Apple requires explicit keys in future builds).
- **Driver** (`Driver/APM44Bridge.entitlements`): empty/minimal dict. HAL plug-ins run in `coreaudiod`; do not enable app sandbox on the driver bundle.

## CI scope

Current repo CI expectation (see [daw-matrix.md](daw-matrix.md)):

- **Automated:** `cmake --build`, `ctest`, offline soak (`scripts/ci-soak.sh`)
- **Manual:** DAW matrix, export bounce QA-02, 30+ min hardware soak, notarization with real Developer ID credentials

Optional future: GitHub Actions `macos-latest` job compiling daemon + tests only (no HAL install, no notary secrets).

## GitHub Actions trust decision

v0.4 keeps official GitHub actions tag-pinned instead of full-length SHA pinned
for the release-adjacent workflows:

- `.github/workflows/release.yml`: `actions/checkout`, `actions/upload-artifact`
- `.github/workflows/sign-notarize.yml`: `actions/checkout`
- `.github/workflows/ci.yml`: `actions/checkout`, `actions/dependency-review-action`

Rationale:

- These are official GitHub-maintained actions.
- Dependabot (`.github/dependabot.yml`) checks GitHub Actions weekly.
- Signing/notarization remains local-maintainer controlled unless a runner is
  explicitly provisioned with Apple credentials.
- Release publication still requires maintainer review of the produced artifact.

Future hardening trigger: before moving more signing, notarization, or release
publication into GitHub-hosted automation, pin critical actions to full-length
SHA revisions and document the refresh procedure.

## Related

- [DAW validation matrix](daw-matrix.md)
- [Export rate check](../scripts/validate-export-rate.sh)
