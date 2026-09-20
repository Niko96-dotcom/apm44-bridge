#!/usr/bin/env bash
# Sign all APM44 Bridge release artifacts with Developer ID Application + Hardened Runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${APM44_BUILD_CONFIG:-Release}"

DAEMON="${APM44_DAEMON_PATH:-$ROOT/build/BridgeDaemon/apm44-bridge}"
APP="${APM44_APP_PATH:-$ROOT/build/$CONFIG/APM44 Bridge.app}"
DRIVER="${APM44_DRIVER_PATH:-$ROOT/build/Driver/APM44Bridge.driver}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: sign-release.sh [--help]

Sign apm44-bridge, APM44 Bridge.app, and APM44Bridge.driver for release.

Environment:
  SIGN_ID              codesign identity. If unset, the script auto-detects
                       a single Developer ID Application identity.
  APM44_DAEMON_PATH    path to apm44-bridge binary
  APM44_APP_PATH       path to .app bundle
  APM44_DRIVER_PATH    path to .driver bundle
  APM44_BUILD_CONFIG   Release or Debug (default Release)

Build first:
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
  bash scripts/embed-daemon-in-app.sh
  bash scripts/verify-app-build.sh   # or xcodebuild Release
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
    return
  fi

  echo "error: set SIGN_ID to your Developer ID Application identity" >&2
  echo "hint: security find-identity -v -p codesigning" >&2
  exit 1
}

SIGN_ID="$(resolve_sign_id)"

sign_one() {
  local target="$1"
  local entitlements="${2:-}"
  if [[ ! -e "$target" ]]; then
    echo "error: missing artifact: $target" >&2
    exit 1
  fi
  echo "Signing: $target"
  local sign_args=(--force --sign "$SIGN_ID" --timestamp --options runtime)
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    codesign "${sign_args[@]}" --entitlements "$entitlements" "$target"
  else
    codesign "${sign_args[@]}" "$target"
  fi
  codesign --verify --verbose "$target"
}

# Re-sign Sparkle helpers inside-out with this Developer ID. Preserve each
# helper's own entitlements (Downloader.xpc in particular; Autoupdate also
# carries com.apple.application-identifier). Do not use --deep: it is
# deprecated for signing and would re-apply host options onto nested code.
sign_sparkle_nested() {
  local app="$1"
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  local sparkle_ver="$sparkle/Versions/Current"
  [[ -d "$sparkle" ]] || return 0
  if [[ ! -d "$sparkle_ver" ]]; then
    echo "error: Sparkle.framework missing Versions/Current in $app" >&2
    exit 1
  fi
  local nested
  for nested in \
    "$sparkle_ver/XPCServices/Downloader.xpc" \
    "$sparkle_ver/XPCServices/Installer.xpc" \
    "$sparkle_ver/Autoupdate" \
    "$sparkle_ver/Updater.app" \
    "$sparkle_ver/Sparkle" \
    "$sparkle"
  do
    if [[ ! -e "$nested" ]]; then
      echo "error: missing Sparkle nested code: $nested" >&2
      exit 1
    fi
    echo "Signing nested: $nested"
    codesign --force --sign "$SIGN_ID" --timestamp --options runtime \
      --preserve-metadata=entitlements "$nested"
    codesign --verify --verbose "$nested"
  done
}

# Inner binaries before outer bundle (app may embed daemon).
if [[ -d "$APP" ]]; then
  sign_sparkle_nested "$APP"
  AUX="$APP/Contents/MacOS/apm44-bridge"
  if [[ -f "$AUX" ]]; then
    sign_one "$AUX"
  fi
fi

sign_one "$DAEMON"
sign_one "$APP" "$ROOT/App/APM44Bridge/APM44Bridge.entitlements"
sign_one "$DRIVER" "$ROOT/Driver/APM44Bridge.entitlements"

echo ""
echo "All artifacts signed with: $SIGN_ID"
echo "Verify deep:"
echo "  codesign --verify --deep --strict \"$APP\""
echo "  codesign --verify --deep --strict \"$DRIVER\""
echo ""
echo "Next: bash scripts/notary-dry-run.sh  (or scripts/notarize-hal-driver.sh for driver only)"
