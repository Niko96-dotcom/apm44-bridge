# Release validation checklist

This checklist is the v0.4 public-release closeout path for the DMG-primary
distribution flow. It separates credential-free verification from Apple
Developer credential checks so local-only artifacts are never confused with a
public release.

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

## Artifact assessment

For the DMG-primary public path, assess these artifacts after
`bash scripts/release-all.sh` succeeds:

```bash
bash scripts/codesign-verify-release.sh
codesign --verify --verbose build/signing/APM44Bridge-0.1.1.dmg
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler validate build/Driver/APM44Bridge.driver
xcrun stapler validate build/signing/APM44Bridge-0.1.1.dmg
spctl --assess --type open --verbose=4 build/signing/APM44Bridge-0.1.1.dmg
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
xcrun stapler validate build/signing/APM44Bridge-0.1.1.dmg
spctl --assess --type open --verbose=4 build/signing/APM44Bridge-0.1.1.dmg
```

If hardware/operator evidence is needed for a final ship decision, run it on a
Mac with the target USB-C AirPods Max and DAW setup:

```bash
bash scripts/verify-hal-driver.sh
build/BridgeDaemon/apm44-bridge --shm-status
```

Then perform the Cubase HAL smoke/soak documented in
`docs/first-run-cubase.md` and `docs/daw-matrix.md`.
