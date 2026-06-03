#!/usr/bin/env bash
# Full maintainer release: build, sign, notarize, and staple the public DMG.
# Set APM44_BUILD_PKG=1 to also attempt the optional signed PKG path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
(cd App && xcodegen generate)

echo "== Build + sign + DMG =="
bash scripts/build-release-dmg.sh

if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE:-AC_NOTARY}" &>/dev/null; then
  echo "== Notarize release zip (app + driver evidence) =="
  bash scripts/notary-dry-run.sh

  echo "== Staple app and driver =="
  xcrun stapler staple "build/Release/APM44 Bridge.app"
  xcrun stapler staple build/Driver/APM44Bridge.driver

  echo "== Notarize DMG (primary distribution) =="
  bash scripts/notarize-release-dmg.sh

  if [[ "${APM44_BUILD_PKG:-0}" == "1" ]]; then
    echo "== Build pkg from stapled artifacts =="
    bash scripts/build-release-pkg.sh
    echo "== Notarize pkg =="
    bash scripts/notarize-release-pkg.sh
  else
    echo "SKIP pkg: DMG is the public release artifact. Set APM44_BUILD_PKG=1 to build/notarize a PKG."
  fi
else
  echo "SKIP notarization: ${NOTARY_PROFILE:-AC_NOTARY} not configured"
fi

echo ""
echo "Release artifacts:"
ls -la build/signing/*.dmg build/signing/*.pkg 2>/dev/null || true
ls -la "build/Release/APM44 Bridge.app" build/Driver/APM44Bridge.driver
