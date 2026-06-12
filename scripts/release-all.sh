#!/usr/bin/env bash
# Full maintainer release: build, sign, notarize, and staple the public DMG.
# Set APM44_BUILD_PKG=1 to also attempt the optional signed PKG path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
NOTARY_READY=0

cd "$ROOT"

if xcrun notarytool history --keychain-profile "$PROFILE" &>/dev/null; then
  NOTARY_READY=1
fi

if [[ "$NOTARY_READY" != "1" && "${APM44_ALLOW_UNNOTARIZED:-0}" != "1" ]]; then
  echo "error: notary profile \"$PROFILE\" is not configured or not usable." >&2
  echo "Public release artifacts must be notarized." >&2
  echo "Configure credentials with scripts/setup-notary-profile.sh, or rerun with" >&2
  echo "APM44_ALLOW_UNNOTARIZED=1 for local-only unnotarized artifacts." >&2
  exit 1
fi

if [[ "$NOTARY_READY" != "1" ]]; then
  echo "WARNING: local-only unnotarized release override enabled." >&2
  echo "Artifacts from this run are LOCAL-ONLY UNNOTARIZED builds, not public release artifacts." >&2
fi

(cd App && xcodegen generate)

echo "== Build + sign + DMG =="
bash scripts/build-release-dmg.sh

if [[ "$NOTARY_READY" == "1" ]]; then
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
  echo "LOCAL-ONLY UNNOTARIZED: skipping notarization because APM44_ALLOW_UNNOTARIZED=1"
fi

echo ""
if [[ "$NOTARY_READY" == "1" ]]; then
  echo "Release artifacts:"
else
  echo "Local-only unnotarized artifacts:"
fi
ls -la build/signing/*.dmg build/signing/*.pkg 2>/dev/null || true
ls -la "build/Release/APM44 Bridge.app" build/Driver/APM44Bridge.driver
