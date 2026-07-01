# Phase 47 Context: Professional DMG Presentation

## Goal

Make the final public DMG expose the validated PKG installer as the primary install object instead of raw app, HAL driver, and Terminal command internals.

## Recommended Scope

Accepted recommended autonomous scope:

1. Change `APM44_DMG_PACKAGE_ONLY=1 bash scripts/build-release-dmg.sh` to stage the validated `.pkg` plus a small readme, not `APM44 Bridge.app`, `APM44Bridge.driver`, or `Install APM44 Bridge.command`.
2. Add a layout verifier that can inspect either a mounted DMG or the package-only staging directory.
3. Add release-script regressions proving the old raw visible contents are rejected.
4. Wire the verifier into `scripts/release-all.sh` before DMG notarization.
5. Add DMG Gatekeeper assessment to `scripts/notarize-release-dmg.sh` before checksum generation.

## Boundaries

- Phase 46 already owns PKG signing, notarization, Gatekeeper assessment, checksum, and provenance.
- Phase 48 owns real final mounted DMG/PKG install, upgrade, and uninstall proof.
- Phase 47 owns presentation/layout and final DMG byte gate.

## Verification

- `bash tests/test_release_scripts.sh`
- `bash scripts/ci.sh`

