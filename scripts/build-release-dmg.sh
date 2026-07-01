#!/usr/bin/env bash
# Build notarized-ready DMG with app + HAL driver (POL-01).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"
VERSION="${APM44_VERSION:-0.12.0}"
OUT="${APM44_DMG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.dmg}"
STAGING="${APM44_DMG_STAGING:-$ROOT/build/signing/dmg-staging}"
PACKAGE_ONLY="${APM44_DMG_PACKAGE_ONLY:-0}"
PKG="${APM44_PKG_PATH:-$ROOT/build/signing/APM44Bridge-${VERSION}.pkg}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: build-release-dmg.sh [--help]

Build Release artifacts, embed daemon, sign, and create a DMG for distribution.

Prerequisites: Developer ID cert, optional notarization (scripts/notary-dry-run.sh)

Environment:
  APM44_DMG_PACKAGE_ONLY=1  package the validated PKG without rebuilding or re-signing

Output: build/signing/APM44Bridge-<version>.dmg
EOF
  exit 0
fi

resolve_sign_id() {
  if [[ -n "${SIGN_ID:-}" ]]; then
    printf '%s\n' "$SIGN_ID"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' || true)"
  local count
  count="$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$identities"
  fi
}

if [[ "$PACKAGE_ONLY" != "1" ]]; then
  echo "Building Release..."
  cmake -S "$ROOT" -B "$ROOT/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$ROOT/build" --target apm44-bridge APM44Bridge

  (cd "$ROOT/App" && xcodegen generate)
  xcodebuild -project "$ROOT/App/APM44Bridge.xcodeproj" -scheme APM44Bridge \
    -configuration "$CONFIG" build CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$ROOT/build/$CONFIG"

  bash "$ROOT/scripts/embed-daemon-in-app.sh"

  if [[ -n "${SIGN_ID:-}" ]] || security find-identity -v -p codesigning | grep -q 'Developer ID Application'; then
    bash "$ROOT/scripts/sign-release.sh"
  fi
else
  echo "Packaging validated pkg into final DMG..."
fi

APP="$ROOT/build/$CONFIG/APM44 Bridge.app"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

rm -rf "$STAGING"
mkdir -p "$STAGING"

if [[ "$PACKAGE_ONLY" == "1" ]]; then
  if [[ ! -f "$PKG" ]]; then
    echo "error: missing $PKG — run scripts/build-release-pkg.sh and scripts/notarize-release-pkg.sh first" >&2
    exit 1
  fi
  ditto "$PKG" "$STAGING/$(basename "$PKG")"
  cat > "$STAGING/README.txt" <<README
APM44 Bridge Installer

Open the PKG in this disk image to install APM44 Bridge.app and the APM44Bridge HAL driver.
macOS will ask for an administrator password because the HAL driver installs into /Library/Audio/Plug-Ins/HAL.
README
else
  for artifact in "$APP" "$DRIVER"; do
    if [[ ! -e "$artifact" ]]; then
      echo "error: missing $artifact — run scripts/build-release-dmg.sh before package-only mode" >&2
      exit 1
    fi
  done

  ditto "$APP" "$STAGING/APM44 Bridge.app"
  ditto "$DRIVER" "$STAGING/APM44Bridge.driver"
  cat > "$STAGING/Install APM44 Bridge.command" <<CMD
#!/bin/bash
set -euo pipefail
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
echo "Installing APM44 Bridge (requires admin password)…"
sudo rm -rf /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo ditto "\$DIR/APM44Bridge.driver" /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver
sudo xattr -cr /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver 2>/dev/null || true
SRC_BIN="\$(find "\$DIR/APM44Bridge.driver/Contents/MacOS" -maxdepth 1 -type f | head -1)"
DST_BIN="\$(find /Library/Audio/Plug-Ins/HAL/APM44Bridge.driver/Contents/MacOS -maxdepth 1 -type f | head -1)"
SRC_SHA="\$(shasum -a 256 "\$SRC_BIN" | awk '{print \$1}')"
DST_SHA="\$(shasum -a 256 "\$DST_BIN" | awk '{print \$1}')"
if [[ "\$SRC_SHA" != "\$DST_SHA" ]]; then
  echo "Installed driver hash mismatch; aborting." >&2
  exit 1
fi
sudo killall coreaudiod 2>/dev/null || true
sudo rm -rf "/Applications/APM44 Bridge.app"
sudo ditto "\$DIR/APM44 Bridge.app" "/Applications/APM44 Bridge.app"
sudo chown -R root:wheel "/Applications/APM44 Bridge.app"
open "/Applications/APM44 Bridge.app"
echo "Done. If APM44 Bridge does not appear in Audio MIDI Setup, reboot once."
CMD
  chmod +x "$STAGING/Install APM44 Bridge.command"
fi

rm -f "$OUT"
hdiutil create -volname "APM44 Bridge" -srcfolder "$STAGING" -ov -format UDZO "$OUT"
DMG_SIGN_ID="$(resolve_sign_id)"
if [[ -n "$DMG_SIGN_ID" ]]; then
  codesign --force --sign "$DMG_SIGN_ID" --timestamp "$OUT"
fi
echo "DMG created: $OUT"
if [[ "$PACKAGE_ONLY" == "1" ]]; then
  echo "Install: open DMG -> open $(basename "$PKG")"
else
  echo "Install: open DMG -> run Install APM44 Bridge.command"
fi
