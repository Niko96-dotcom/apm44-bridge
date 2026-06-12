# 16-02 Summary: Artifact Assessment and Closeout Caveats

**Completed:** 2026-06-12
**Status:** Complete

## Work Completed

- Ran live release preflight on the maintainer machine.
- Confirmed one valid Developer ID Application identity is available.
- Confirmed `AC_NOTARY` is usable via `xcrun notarytool history`.
- Ran the real public release command:

```bash
bash scripts/release-all.sh
```

- Validated that `release-all.sh` built and signed Release artifacts, submitted
  the app/driver evidence zip, stapled and validated the inner app/driver,
  repackaged the final DMG from stapled inner artifacts, submitted the final
  DMG, stapled it, and validated it.
- Updated `docs/release-validation.md` after catching that DMG Gatekeeper
  assessment requires `--context context:primary-signature`; the corrected
  command passed.
- Updated `.planning/PROJECT.md` with v0.4 release-validation closure, satisfied
  blocker requirements, and accepted public-release caveats.

## Requirements Closed

- QA-03: Final DMG-primary artifact path was checked with `codesign`,
  `stapler validate`, `spctl`, and `hdiutil verify`.
- QA-04: No Apple credential blocker remained on this machine. Exact unblock
  commands for credentials, notary profile, stapler, Gatekeeper, PKG validation,
  and hardware/operator evidence remain documented in `docs/release-validation.md`.
- QA-05: Planning state now records satisfied requirements, accepted caveats,
  and the remaining operator-dependent public-release steps.

## Live Release Evidence

Credential preflight:

- `security find-identity -v -p codesigning` found one valid Developer ID
  Application identity.
- `xcrun notarytool history --keychain-profile AC_NOTARY` succeeded.

Release command:

```bash
bash scripts/release-all.sh
```

Key results:

- Release build id: `0.1.1+d5efb41ec1ca`.
- App/driver evidence zip submission id:
  `cd75ded5-9cf3-4d4e-824e-62f620882d9b`, status `Accepted`.
- Inner `APM44 Bridge.app` stapler validation: passed.
- Inner `APM44Bridge.driver` stapler validation: passed.
- Final DMG submission id: `a0d1c64b-d45b-4e17-bc85-a4d3d78ff562`,
  status `Accepted`.
- Final DMG stapler validation: passed.
- Public DMG path: `build/signing/APM44Bridge-0.1.1.dmg`.
- Public DMG size: 2.2 MB.
- Public DMG SHA-256:
  `64653ec98e2a7ada4b3fa6c73f905f467a2851a3cbeb39cb35070aefcd973d16`.
- PKG path skipped by design: `APM44_BUILD_PKG` was not set, and the DMG is the
  public release artifact.

Artifact assessment:

```bash
bash scripts/codesign-verify-release.sh
codesign --verify --verbose build/signing/APM44Bridge-0.1.1.dmg
xcrun stapler validate "build/Release/APM44 Bridge.app"
xcrun stapler validate build/Driver/APM44Bridge.driver
xcrun stapler validate build/signing/APM44Bridge-0.1.1.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 build/signing/APM44Bridge-0.1.1.dmg
hdiutil verify build/signing/APM44Bridge-0.1.1.dmg
```

Results:

- `codesign-verify-release: passed`.
- Daemon, app, and driver verify with Developer ID Application and hardened runtime.
- DMG codesign verification passed.
- App, driver, and DMG stapler validation passed.
- Gatekeeper accepted the DMG with `source=Notarized Developer ID`.
- `hdiutil verify` reported the DMG checksum as valid.

## Deviations from Plan

- The initially planned Gatekeeper command,
  `spctl --assess --type open --verbose=4 build/signing/APM44Bridge-0.1.1.dmg`,
  returned `rejected` with `source=Insufficient Context`.
- The correct DMG assessment command adds
  `--context context:primary-signature`; it passed and the docs/plan were
  updated accordingly.

## Follow-Up

- Uploading the DMG to GitHub Releases remains an operator/publication action.
- PKG remains maintainer-only/future unless `APM44_BUILD_PKG=1` is intentionally
  run with Developer ID Installer validation.
- Live USB-C AirPods/Cubase soak is still operator-dependent hardware evidence,
  not a blocker for the automated and release-artifact validation closure.
