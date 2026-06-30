# Release validation checklist

This checklist is the current 0.11.0 DMG-primary distribution validation path.
It separates credential-free verification
from Apple Developer credential checks so local-only artifacts are never
confused with a public release.

## Final automated verification

Run the full local gate before using release credentials:

```bash
bash scripts/ci.sh
```

Expected coverage:

- secret scan,
- CMake configure and native build,
- native Catch2/CTest suite,
- release-script regression tests,
- Swift app build verification,
- Swift unit tests,
- daemon embedding into the app bundle, and
- installed-sync dry-run.

The run must end with:

```text
ci: OK
```

## Clean public release sequence

Start from a clean checkout or remove stale build artifacts:

```bash
git status --short
rm -rf build
bash scripts/ci.sh
```

Confirm release credentials are available:

```bash
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile "${NOTARY_PROFILE:-AC_NOTARY}"
```

Build, sign, notarize, staple, and validate the public DMG:

```bash
bash scripts/release-all.sh
```

`release-all.sh` must use this order:

1. Build Release app, daemon, and HAL driver.
2. Embed the current daemon into `APM44 Bridge.app`.
3. Sign the daemon, app, and driver.
4. Submit the app/driver evidence zip and require `status: Accepted`.
5. Staple and validate the inner app and driver.
6. Package the final DMG from those stapled inner artifacts.
7. Notarize, staple, and validate the final public DMG.

## Public tree hygiene

Before tagging or publishing release assets, verify that the public Git tree
does not include local planning state, macOS metadata, credential-shaped files,
or private release logs:

```bash
git ls-files | rg '(^|/)\.DS_Store$|^\.planning/|(^|/)\.env($|\.)|\.(p8|p12|pem|key)$|notary-log.*\.json$|build/signing/cert-request/'
```

Expected result: no output.

The local `.planning/` directory is for GSD workflow state only. Keep it ignored
and untracked for public releases. Public release evidence belongs in
`CHANGELOG.md`, `docs/release-validation.md`, GitHub release notes, and linked
issues or PRs.

## Release-Mac validation commands

Run these on the release Mac before tagging or uploading a public artifact:

```bash
# 1. Secrets and toolchain
bash scripts/check-secrets.sh
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile "${NOTARY_PROFILE:-AC_NOTARY}"

# 2. Build and local regression proof
rm -rf build
bash scripts/ci.sh

# 3. Release build, signing, notarization, stapling, and DMG packaging
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
bash scripts/release-all.sh

# 4. Artifact signing/notary assessment
bash scripts/codesign-verify-release.sh
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler validate build/Driver/APM44Bridge.driver
xcrun stapler validate "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"

# 5. Installed app / HAL checks after installing from the DMG
APM44_APP_PATH="/Applications/APM44 Bridge.app" bash scripts/verify-installed-sync.sh
bash scripts/verify-hal-driver.sh
build/BridgeDaemon/apm44-bridge --shm-status
```

## Target-hardware operator validation

Run this on the target Mac with USB-C AirPods Max and Cubase available:

```bash
# 1. Clean install from the final DMG
hdiutil attach "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
# Run "Install APM44 Bridge.command" from the mounted DMG.
# Reboot once if Audio MIDI Setup does not show the HAL device after install.

# 2. HAL visibility and installed build identity
APM44_APP_PATH="/Applications/APM44 Bridge.app" bash scripts/verify-installed-sync.sh
bash scripts/verify-hal-driver.sh
build/BridgeDaemon/apm44-bridge --shm-status

# 3. Menu-bar app start and DAW route
open "/Applications/APM44 Bridge.app"
# In Audio MIDI Setup: APM44 Bridge at 44,100 Hz; USB-C AirPods at 48,000 Hz.
# In Cubase: select APM44 Bridge as the audio output and assign Control Room Monitor L/R to APM44 Bridge.

# 4. Smoke, soak, and export-rate proof
# Play a 440 Hz tone and confirm menu bar state reaches Running.
# Complete docs/cubase-soak.md for a 30+ minute hardware soak.
bash scripts/validate-export-rate.sh --check-file ~/Desktop/your-mix.wav
```

Record command output and operator notes in the release issue or tag checklist.

## Artifact assessment

For the DMG-primary public path, assess these artifacts after
`bash scripts/release-all.sh` succeeds:

```bash
bash scripts/codesign-verify-release.sh
codesign --verify --verbose "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler validate build/Driver/APM44Bridge.driver
xcrun stapler validate "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
```

The final command is the Gatekeeper assessment for the public DMG.

Optional maintainer-only PKG validation is intentionally separate:

```bash
APM44_BUILD_PKG=1 bash scripts/release-all.sh
pkgutil --check-signature build/signing/*.pkg
spctl --assess --type install --verbose=4 build/signing/*.pkg
```

Do not treat the PKG as the primary public artifact until Developer ID Installer
signing and installer UX validation are complete.

## Local-only override

This command is for packaging inspection only:

```bash
APM44_ALLOW_UNNOTARIZED=1 bash scripts/release-all.sh
```

Artifacts from that run are local-only unnotarized builds. They are not
public-release-ready and must not be uploaded as release assets.

## Unblock commands

If `security find-identity -v -p codesigning` does not show exactly one usable
Developer ID Application identity, install or select the certificate, then rerun:

```bash
security find-identity -v -p codesigning
export SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

If the notary profile check fails, create or refresh the notary profile:

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "<app-specific-password>"
xcrun notarytool history --keychain-profile "AC_NOTARY"
```

If stapler validation fails after notarization, fetch the notary log and rerun
the relevant release command:

```bash
xcrun notarytool log <submission-id> --keychain-profile "${NOTARY_PROFILE:-AC_NOTARY}" notary-log.json
bash scripts/release-all.sh
```

If Gatekeeper assessment fails, inspect the signature and stapled ticket before
repackaging:

```bash
bash scripts/codesign-verify-release.sh
xcrun stapler validate "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "build/signing/APM44Bridge-${APM44_VERSION:-0.11.0}.dmg"
```

If hardware/operator evidence is needed for a final ship decision, run it on a
Mac with the target USB-C AirPods Max and DAW setup:

```bash
bash scripts/verify-hal-driver.sh
build/BridgeDaemon/apm44-bridge --shm-status
```

Then perform the Cubase HAL smoke/soak documented in
`docs/first-run-cubase.md` and `docs/daw-matrix.md`.
