#!/usr/bin/env bash
# Full maintainer release: build, sign, notarize app+driver, pkg, staple.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
(cd App && xcodegen generate)

echo "== Build + sign + DMG =="
bash scripts/build-release-dmg.sh

echo "== Notarize release zip (app + driver evidence) =="
bash scripts/notary-dry-run.sh

echo "== Staple app and driver =="
xcrun stapler staple "build/Release/APM44 Bridge.app"
xcrun stapler staple build/Driver/APM44Bridge.driver

echo "== Build pkg from stapled artifacts =="
bash scripts/build-release-pkg.sh || true

if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE:-AC_NOTARY}" &>/dev/null; then
  echo "== Notarize DMG (primary distribution without Installer cert) =="
  bash scripts/notarize-release-dmg.sh
  if security find-identity -v | grep -q "Developer ID Installer"; then
    echo "== Notarize pkg =="
    bash scripts/notarize-release-pkg.sh
  else
    echo "SKIP pkg notarize: no Developer ID Installer cert — use DMG for distribution"
    echo "  Create cert: developer.apple.com → Certificates → Developer ID Installer"
  fi
else
  echo "SKIP: AC_NOTARY not configured"
fi

echo ""
echo "Release artifacts:"
ls -la build/signing/*.pkg build/signing/*.dmg 2>/dev/null || true
ls -la "build/Release/APM44 Bridge.app" build/Driver/APM44Bridge.driver
